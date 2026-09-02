import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "BarModel.js" as BarModel

// The bar's focus ring: keyboard and controller navigation over the bar's own
// icons, one stop per thing a mouse could click.
//
// The bar has been keyboard-driven for a while, but only once a panel is open —
// `Super+Ctrl+<letter>` names a panel, `Super+Ctrl+1-9` counts them, and Tab
// inside one steps to its neighbour. What there was no way to do was point at a
// bar *icon* without a mouse: the bar surface never takes keyboard focus, and
// the widgets with no panel of their own (workspaces, indicators, the tray
// chevron, a custom module) were unreachable however you tabbed. This is that
// missing half, and it is also what makes the bar usable from a TV remote or a
// game controller, where there is no pointer at all.
//
// ## What it is built on, and why none of it can drift
//
//   * The stops are `bar.clickTargets` — every `WidgetButton` registers itself
//     there — filtered by `bar.moduleTargetClickable`. So the ring's stops are
//     exactly what a mouse can click, and a widget that hides itself or an
//     indicator that is concealed drops out for free, with no second list to
//     keep in step.
//   * Activate is `target.triggerPress(button)`: the same call the widget's own
//     MouseArea makes. Return and a right-arrow-free "activate" therefore mean
//     precisely what a click means, including for third-party widgets nobody
//     here has seen. A secondary activate is `Qt.RightButton`, which is how the
//     right-click actions with no IPC verb — audio's mute-all, the clock's
//     format cycle — become reachable without a pointer.
//   * Yielding is `bar.activePopout`: when activating opens a panel, that panel
//     takes the keyboard and this surface drops its focus, then takes it back
//     when the panel closes. Which gives the console idiom in one line —
//     Escape in a panel closes it and lands you back on the ring; Escape on the
//     ring leaves the bar.
//
// ## Why a separate surface rather than focusing the bar
//
// The bar must never hold the keyboard: it is always mapped, so focusing it
// would take typing away from every application. Instead, while the ring is up,
// a 1x1 click-through layer surface is mapped with the namespace
// `omarchy-bar-nav`. Nothing is drawn on it. Both its jobs are invisible — it
// holds the keyboard, and its namespace is visible in `hyprctl layers`, which
// is how an outside agent (hyprpad's controller daemon, keyed on
// `openlayer`/`closelayer`) can tell that the bar is in navigation mode and
// route its D-pad, A and B accordingly without a single per-press round trip.
//
// The focus prime — Exclusive at map time, then OnDemand ~75ms later — is
// copied from Ui/KeyboardPanel.qml, not invented. Hyprland grants an OnDemand
// surface focus when it first maps but not when an already-mapped one asks for
// it back, and Exclusive routes every pointer event compositor-wide to the
// surface for as long as it lasts, so it has to be brief.
Item {
  id: root

  required property var bar

  // Which bar section the ring lands on when it is raised cold. The right one
  // by default: audio, network, Bluetooth, display and power all live there.
  property string startRegion: "right"

  property bool active: false
  // The focused click target, the ring drawn on it, and the bar surface the
  // ring is confined to (one bar exists per monitor).
  property var target: null
  property var ring: null
  property var barWindow: null
  // Where the ring was when navigation was last left, so re-entering resumes.
  property var lastTarget: null
  property bool primed: false

  // A panel owns the keyboard while it is open. The surface stays MAPPED — an
  // outside agent must keep seeing the namespace — and only drops its focus.
  readonly property bool yielded: root.active && !!(root.bar && root.bar.activePopout)

  readonly property string barPosition: root.bar ? String(root.bar.position || "top") : "top"

  // --- the ring's stops ----------------------------------------------------

  // The ModuleSlot a click target sits in, so a stop can say which bar section
  // it belongs to. Bounded: a target is a handful of items below its slot.
  function slotFor(item) {
    if (!root.bar) return null
    var slots = root.bar.moduleSlots || []
    var node = item
    for (var guard = 0; node && guard < 12; guard++) {
      if (slots.indexOf(node) !== -1) return node
      node = node.parent
    }
    return null
  }

  function rows() {
    var out = []
    if (!root.bar || !root.barWindow) return out
    var content = root.barWindow.contentItem
    var targets = root.bar.clickTargets || []
    for (var i = 0; i < targets.length; i++) {
      var item = targets[i]
      if (!root.bar.moduleTargetClickable(item)) continue
      if (!root.bar.targetBelongsToWindow(item, root.barWindow)) continue
      var pos = null
      try {
        pos = item.mapToItem(content, 0, 0)
      } catch (e) {
        continue
      }
      if (!pos) continue
      var slot = root.slotFor(item)
      out.push({
        target: item,
        x: pos.x,
        y: pos.y,
        width: item.width,
        height: item.height,
        region: slot ? String(slot.region || "") : ""
      })
    }
    return BarModel.navOrder(out, root.bar.vertical === true)
  }

  function stops() {
    return root.rows().map(function(row) { return row.target })
  }

  // The bar surface the ring belongs on: the one Hyprland has focused, which is
  // the same rule panel hotkeys follow. With no focused output reported, the
  // first surface that registered a slot wins — arbitrary, but stable.
  function pickWindow() {
    if (!root.bar) return null
    var focused = typeof root.bar.focusedScreenName === "function" ? root.bar.focusedScreenName() : ""
    var fallback = null
    var slots = root.bar.moduleSlots || []
    for (var i = 0; i < slots.length; i++) {
      var window = root.bar.slotWindow(slots[i])
      if (!window) continue
      if (!fallback) fallback = window
      if (focused && window.screen && String(window.screen.name || "") === focused) return window
    }
    return fallback
  }

  // --- moving ---------------------------------------------------------------

  function setTarget(next) {
    var previous = root.target
    if (root.ring) {
      root.ring.destroy()
      root.ring = null
    }
    root.target = next || null
    if (root.target) root.lastTarget = root.target

    if (root.active && root.target) {
      root.ring = ringComponent.createObject(root.target)
      // The focused widget names itself. `targetTooltipHovered` counts the
      // ring's target as hovered, which is the two-word change in Bar.qml that
      // makes this work without a second tooltip path.
      if (typeof root.bar.showTooltip === "function")
        root.bar.showTooltip(root.target, String(root.target.tooltipText || ""))
    } else if (previous && root.bar && typeof root.bar.hideTooltip === "function") {
      root.bar.hideTooltip(previous)
    }
  }

  function step(delta) {
    if (!root.active) return
    var list = root.stops()
    if (list.length === 0) {
      root.leave()
      return
    }
    root.setTarget(list[BarModel.navStepIndex(list.length, list.indexOf(root.target), delta)])
  }

  function press(button) {
    if (!root.active || !root.target) return
    if (typeof root.target.triggerPress !== "function") return
    root.target.triggerPress(button)
  }

  // --- entering and leaving -------------------------------------------------

  // Refused on a hidden bar: `barHidden` parks the surface past the screen
  // edge, so there would be a ring on something nobody can see.
  function enter() {
    if (!root.bar || root.bar.barHidden === true) return false
    root.barWindow = root.pickWindow()
    var list = root.rows()
    if (list.length === 0) {
      root.barWindow = null
      return false
    }
    var targets = list.map(function(row) { return row.target })
    var resume = root.lastTarget && targets.indexOf(root.lastTarget) !== -1
      ? root.lastTarget
      : targets[Math.max(0, BarModel.navStartIndex(list, root.startRegion))]
    root.active = true
    root.setTarget(resume)
    return true
  }

  function leave() {
    if (!root.active && !root.ring) return
    root.active = false
    root.setTarget(null)
    root.barWindow = null
  }

  function toggle() {
    if (root.active) {
      root.leave()
      return false
    }
    return root.enter()
  }

  // --- keeping up with the bar ---------------------------------------------

  // Tab inside an open panel walks to the neighbouring panel, which moves the
  // bar out from under the ring. Follow it, so closing the panel lands the ring
  // where the user actually ended up.
  function syncToPopout() {
    if (!root.active || !root.bar) return
    var owner = root.bar.activePopout
    if (!owner) return
    var list = root.stops()
    for (var i = 0; i < list.length; i++) {
      var node = list[i]
      for (var guard = 0; node && guard < 12; guard++) {
        if (node === owner) {
          if (list[i] !== root.target) root.setTarget(list[i])
          return
        }
        node = node.parent
      }
    }
  }

  // The registry changed under us: a widget hid itself, a workspace closed, a
  // plugin was toggled. Deferred, because this can arrive from the focused
  // target's own destruction.
  function revalidate() {
    if (root.active) Qt.callLater(root.revalidateNow)
  }

  function revalidateNow() {
    if (!root.active) return
    var list = root.rows()
    if (list.length === 0) {
      root.leave()
      return
    }
    var targets = list.map(function(row) { return row.target })
    if (targets.indexOf(root.target) === -1)
      root.setTarget(targets[Math.max(0, BarModel.navStartIndex(list, root.startRegion))])
  }

  function beginPrime() {
    if (root.active && !root.yielded && navSurface.backingWindowVisible) primeTimer.restart()
  }

  function takeFocus() {
    root.primed = false
    root.beginPrime()
    Qt.callLater(function() {
      if (root.active && !root.yielded) keyCatcher.forceActiveFocus()
    })
  }

  function handleKey(event) {
    if (!root.active) return
    var name = ""
    switch (event.key) {
      case Qt.Key_Escape: name = "escape"; break
      case Qt.Key_Back: name = "back"; break
      case Qt.Key_Return: name = "return"; break
      case Qt.Key_Enter: name = "enter"; break
      case Qt.Key_Space: name = "space"; break
      case Qt.Key_Tab: name = "tab"; break
      case Qt.Key_Backtab: name = "backtab"; break
      case Qt.Key_Left: name = "left"; break
      case Qt.Key_Right: name = "right"; break
      case Qt.Key_Up: name = "up"; break
      case Qt.Key_Down: name = "down"; break
      default: return
    }

    var role = BarModel.navKeyRole(name, root.barPosition)
    if (role === "next") root.step(1)
    else if (role === "prev") root.step(-1)
    else if (role === "activate") root.press(Qt.LeftButton)
    else if (role === "leave") root.leave()
    else return

    event.accepted = true
  }

  onActiveChanged: {
    if (root.active) root.takeFocus()
    else {
      primeTimer.stop()
      root.primed = false
    }
  }

  // A panel closed and handed the keyboard back.
  onYieldedChanged: if (root.active && !root.yielded) root.takeFocus()

  // The surface the ring was drawn on went away with its monitor.
  onBarWindowChanged: if (root.active && !root.barWindow) root.leave()

  Timer {
    id: primeTimer
    interval: 75
    onTriggered: if (root.active) root.primed = true
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onActivePopoutChanged() { root.syncToPopout() }
    function onClickTargetsChanged() { root.revalidate() }
    function onBarHiddenChanged() { if (root.bar && root.bar.barHidden === true) root.leave() }
  }

  // The ring is CREATED as a child of the focused target rather than reparented
  // onto it. It then tracks that widget's geometry with a plain anchor, paints
  // inside that widget's own slot (so it cannot end up behind a neighbour), and
  // — the reason for creating rather than moving one — dies with the target if
  // the widget goes away underneath it. A workspace button vanishing along with
  // its workspace is a real case; the ring is rebuilt on the next step.
  Component {
    id: ringComponent

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(1)
      z: 60
      radius: Math.min(Style.cornerRadius, Math.min(width, height) / 2)
      // The open-panel dot's idiom grown into an outline, so "focused" and
      // "open" read as the same family without being the same mark.
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
      border.color: Color.accent
      border.width: Math.max(1, Style.space(1))

      OpacityAnimator on opacity {
        from: 0
        to: 1
        duration: 90
      }
    }
  }

  PanelWindow {
    id: navSurface

    visible: root.active
    screen: root.barWindow ? root.barWindow.screen : null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 1
    implicitHeight: 1

    anchors {
      top: true
      left: true
    }

    // Empty input region: every pixel of the bar underneath stays clickable
    // with the mouse while the ring is up.
    mask: Region {}

    WlrLayershell.namespace: "omarchy-bar-nav"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.active && !root.yielded
      ? (root.primed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    // The map is when focus can actually be taken, so the prime starts there
    // rather than from the state change that asked for it.
    onBackingWindowVisibleChanged: if (backingWindowVisible) root.takeFocus()

    // Layer-shell grants focus to the SURFACE; Qt still needs an item inside it
    // holding active focus before Keys.onPressed will fire.
    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }
    }
  }
}
