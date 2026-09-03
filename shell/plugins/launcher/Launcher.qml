import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "LauncherModel.js" as LauncherModel

// Fullscreen application grid for gamepad-first launching (Hyprpad).
//
// Summon with `omarchy launcher` (toggle) or shell IPC:
//   omarchy-shell shell toggle omarchy.launcher
//
// D-pad contract for Hyprland controller mappings — bind gamepad inputs to
// these keys and the grid behaves: arrows move in 2D across pages, Enter
// launches, `p` pins, PageUp/PageDown turn pages, Escape closes. Typing
// filters; mouse hover selects and click launches.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property int currentPage: 0
  property bool cursorActive: false
  property var pins: []
  property var rows: []

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property string pluginId: (root.manifest && root.manifest.id) || "omarchy.launcher"
  readonly property string pinsPath: Quickshell.env("HOME") + "/.config/omarchy/launcher-pins"

  // Menu-surface tokens so themes style the launcher with the menu.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md

  // Tile sizing: fixed cell, column count follows the window width so a
  // gamepad grid stays regular on any monitor.
  property int cellWidth: Style.space(150)
  property int cellHeight: Style.space(150)
  property int columns: Math.max(3, Math.floor(gridArea.width / cellWidth))
  property int gridRows: Math.max(2, Math.floor(gridArea.height / cellHeight))
  property int perPage: Math.max(1, columns * gridRows)
  // The bar renders above this overlay, so inset the content sheet clear of
  // it. Third-party bars may not expose these; anything unknown means no
  // inset rather than a broken binding.
  readonly property var liveBar: root.shell ? root.shell.bar : null
  readonly property int sheetMargin: Math.max(Style.gapsOut, Style.space(24))
  readonly property int barTop: (liveBar && liveBar.position === "top" && liveBar.barHidden === false) ? (liveBar.barSize || 0) : 0
  readonly property int barBottom: (liveBar && liveBar.position === "bottom" && liveBar.barHidden === false) ? (liveBar.barSize || 0) : 0
  readonly property int barLeft: (liveBar && liveBar.position === "left" && liveBar.barHidden === false) ? (liveBar.barSize || 0) : 0
  readonly property int barRight: (liveBar && liveBar.position === "right" && liveBar.barHidden === false) ? (liveBar.barSize || 0) : 0
  // Plain (not bound) so layout settling — columns/gridRows fluttering while
  // the window sizes — cannot feed back through rebuildDisplay into itself.
  property int totalPages: 1

  onPerPageChanged: root.rebuildDisplay()
  onOpenedChanged: {
    if (!opened) {
      filterText = ""
      return
    }
    currentPage = 0
    selectedIndex = 0
    cursorActive = false
    filterText = ""
    if (root.appLibrary) root.appLibrary.refreshIcons()
    pinsFile.reload()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened) root.rebuildDisplay() }
  }

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function ping() { return "ok" }

  function geometry() {
    return JSON.stringify({
      columns: root.columns,
      gridRows: root.gridRows,
      perPage: root.perPage,
      rows: root.rows.length,
      page: root.currentPage,
      totalPages: root.totalPages,
      gridW: Math.round(gridArea.width),
      gridH: Math.round(gridArea.height),
      cellW: grid.cellWidth,
      cellH: grid.cellHeight,
      model: displayModel.count,
      barTop: root.barTop,
      selectedIndex: root.selectedIndex,
      cursorActive: root.cursorActive,
      filterText: root.filterText,
      opened: root.opened
    })
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function collectEntries() {
    if (!root.appLibrary) return []
    var found = root.appLibrary.sortedEntries("")
    var out = []
    for (var i = 0; i < found.length; i++) {
      var entry = found[i] ? found[i].entry : null
      if (!entry) continue
      var id = LauncherModel.normalizeId(entry.id)
      if (!id) continue
      out.push({
        id: id,
        name: root.appLibrary.entryName(entry),
        subtext: root.appLibrary.entrySubtext(entry),
        icon: String(entry.icon || "")
      })
    }
    return out
  }

  function rebuildDisplay() {
    var next = LauncherModel.buildRows(root.collectEntries(), root.pins, root.filterText)
    root.rows = next
    root.totalPages = LauncherModel.pageCount(next.length, root.perPage)
    root.currentPage = LauncherModel.clampPage(root.currentPage, next.length, root.perPage)
    if (next.length === 0) {
      selectedIndex = 0
    } else if (selectedIndex >= next.length) {
      selectedIndex = next.length - 1
    } else if (selectedIndex < 0) {
      selectedIndex = 0
    }
    // Keep the cursor on the visible page after a filter or rescan.
    var start = root.currentPage * root.perPage
    if (next.length > 0 && (selectedIndex < start || selectedIndex > start + root.perPage - 1)) {
      selectedIndex = Math.min(start, next.length - 1)
    }
    cursorActive = next.length > 0

    displayModel.clear()
    var end = Math.min(next.length, start + root.perPage)
    for (var i = start; i < end; i++) {
      displayModel.append({
        appId: next[i].appId,
        label: next[i].label,
        subtext: next[i].subtext,
        icon: next[i].icon,
        pinned: next[i].pinned,
        globalIndex: i
      })
    }
  }

  function pageStart() { return root.currentPage * root.perPage }

  function selectGlobal(index) {
    if (root.rows.length === 0) return
    var at = Math.min(Math.max(0, index), root.rows.length - 1)
    root.currentPage = LauncherModel.clampPage(Math.floor(at / root.perPage), root.rows.length, root.perPage)
    root.selectedIndex = at
    root.cursorActive = true
    root.rebuildDisplay()
  }

  // Mouse hover path: only rebuilds the page slice when the hovered tile
  // is on another page. Rebuilding on every hover would recreate the
  // delegate whose MouseArea is mid-signal.
  function hoverTile(globalIndex) {
    if (root.rows.length === 0) return
    // Clamp: GridView recycles delegate instances across model resets, so a
    // motion event can briefly arrive carrying the previous model's index.
    var at = Math.min(Math.max(0, globalIndex), root.rows.length - 1)
    var page = LauncherModel.clampPage(Math.floor(at / root.perPage), root.rows.length, root.perPage)
    root.selectedIndex = at
    root.cursorActive = true
    if (page !== root.currentPage) {
      root.currentPage = page
      root.rebuildDisplay()
    }
  }

  function move(key) {
    if (root.rows.length === 0) return
    var next = LauncherModel.moveCursor(root.currentPage, root.selectedIndex, root.rows.length, root.columns, root.perPage, key)
    root.currentPage = next.page
    root.selectedIndex = next.index
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function turnPage(delta) {
    if (root.rows.length === 0) return
    var next = LauncherModel.clampPage(root.currentPage + delta, root.rows.length, root.perPage)
    if (next === root.currentPage) return
    root.currentPage = next
    root.selectedIndex = Math.min(next * root.perPage, root.rows.length - 1)
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.currentPage = 0
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function activateSelected() {
    if (!root.cursorActive || root.rows.length === 0) return
    var row = root.rows[selectedIndex]
    if (!row) return
    root.dismiss()
    if (root.appLibrary) root.appLibrary.launch(row.appId, row.label)
  }

  function togglePinSelected() {
    if (!root.cursorActive || root.rows.length === 0) return
    var row = root.rows[selectedIndex]
    if (!row) return
    root.pins = LauncherModel.togglePin(root.pins, row.appId)
    root.savePins()
    root.rebuildDisplay()
  }

  function savePins() {
    savePinsProc.command = ["bash", "-c", "mkdir -p " + Util.shellQuote(Quickshell.env("HOME") + "/.config/omarchy") + " && printf '%s' " + Util.shellQuote(LauncherModel.serializePins(root.pins)) + " > " + Util.shellQuote(root.pinsPath)]
    savePinsProc.running = true
  }

  function loadPins(raw) {
    root.pins = LauncherModel.parsePins(raw)
    if (root.opened) root.rebuildDisplay()
  }

  ListModel { id: displayModel }

  FileView {
    id: pinsFile
    path: root.pinsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPins(text())
    onFileChanged: reload()
    onLoadFailed: root.loadPins("")
  }

  Process { id: savePinsProc }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: sheet
      anchors.fill: parent
      anchors.topMargin: root.barTop + root.sheetMargin
      anchors.bottomMargin: root.barBottom + root.sheetMargin
      anchors.leftMargin: root.barLeft + root.sheetMargin
      anchors.rightMargin: root.barRight + root.sheetMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.move("Left")
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.move("Right")
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.move("Up")
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.move("Down")
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.turnPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.turnPage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectGlobal(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectGlobal(root.rows.length - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_P && event.modifiers === Qt.NoModifier && !root.filterText) {
            // Bare `p` pins only outside a search so typing a filter
            // containing "p" never pins by accident. Clear with Esc, then pin.
            root.togglePinSelected()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      // Anchored (not hand-computed) layout: the header docks top, the page
      // row docks bottom, and the grid fills exactly what remains, so no
      // row can ever run under the screen edge.
      Text {
        id: headerText
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.filterText || "Applications"
        color: root.foreground
        opacity: root.filterText ? 1 : 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        elide: Text.ElideRight
      }

      Item {
        id: pageRow
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: pageText.implicitHeight + Style.space(8)

        Text {
          id: pageText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.totalPages > 1 ? pageRow.pageDots() : pageRow.hintText()
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        function pageDots() {
          var parts = []
          for (var i = 0; i < root.totalPages && i < 21; i++) parts.push(i === root.currentPage ? "●" : "○")
          return parts.join(" ") + "   " + hintText()
        }

        function hintText() {
          return "Arrows move · Enter launches · P pins · Esc closes"
        }
      }

      Item {
        id: gridArea
        anchors.top: headerText.bottom
        anchors.topMargin: root.contentSpacing
        anchors.bottom: pageRow.top
        anchors.bottomMargin: root.contentSpacing
        anchors.left: parent.left
        anchors.right: parent.right

          GridView {
            id: grid
            anchors.fill: parent
            model: displayModel
            clip: true
            interactive: false
            cellWidth: Math.floor(gridArea.width / Math.max(1, root.columns))
            cellHeight: Math.floor(gridArea.height / Math.max(1, root.gridRows))
            boundsBehavior: Flickable.StopAtBounds

            Text {
              anchors.centerIn: parent
              visible: root.opened && root.rows.length === 0
              textFormat: Text.PlainText
              text: root.filterText ? ("No matches for “" + root.filterText + "”") : "No applications found"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            delegate: Item {
              required property int index
              required property string appId
              required property string label
              required property string subtext
              required property string icon
              required property bool pinned
              required property int globalIndex

              readonly property bool hasCursor: root.cursorActive && globalIndex === root.selectedIndex

              width: grid.cellWidth
              height: grid.cellHeight

              Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.space(12), root.cellWidth - Style.space(12))
                height: Math.min(parent.height - Style.space(12), root.cellHeight - Style.space(12))
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : root.background
                border.color: hasCursor ? root.selectedBorder : root.border
                border.width: hasCursor ? Math.max(1, Style.space(2)) : 1

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.spacing.md
                  spacing: Style.spacing.xs

                  Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(52)
                    height: Style.space(52)
                    source: root.appLibrary ? root.appLibrary.iconSource(icon) : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    // Desktop entries sometimes point at icon files that no
                    // longer exist (stale webapp icons); fall back to the
                    // generic app glyph once rather than leaving a hole.
                    property bool iconFailed: false
                    onStatusChanged: if (status === Image.Error && !iconFailed && root.appLibrary) {
                      iconFailed = true
                      source = root.appLibrary.iconSource("")
                    }
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: (pinned ? "★ " : "") + label
                    color: hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  // Position changes only: containsMouse also fires when
                  // delegates are recreated under a stationary pointer
                  // (every keyboard move rebuilds the page), which would
                  // yank the cursor back to the parked tile and make pad
                  // navigation fight the mouse. Real pointer motion is the
                  // only thing that takes the cursor.
                  onPositionChanged: root.hoverTile(globalIndex)
                  onClicked: {
                    root.selectedIndex = globalIndex
                    root.cursorActive = true
                    root.activateSelected()
                  }
                }
              }
            }
          }
        }
      }

    }
  }
