#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export OMARCHY_PATH="$ROOT"

run_node_test <<'JS'
const fs = require('fs')
const bar = requireFromRoot('shell/plugins/bar/BarModel.js')
const barSource = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')
const navSource = fs.readFileSync(root + '/shell/plugins/bar/BarNavigator.qml', 'utf8')
const shellDocs = fs.readFileSync(root + '/docs/omarchy-shell.md', 'utf8')

// ---------------------------------------------------------------- ring order

// The ring walks the bar the way it is read, not the order widgets happened to
// register in: registration is per-widget and arrives with layout, so it says
// nothing about where anything ended up.
const stop = (target, x, extra) => Object.assign(
  { target, x, y: 0, width: 27, height: 26, region: 'right' },
  extra || {}
)
const scrambled = [
  stop('power', 2013),
  stop('workspace-1', 8, { region: 'left' }),
  stop('bluetooth', 1905),
  stop('clock', 969, { region: 'center' })
]
assertDeepEqual(
  bar.navOrder(scrambled, false).map(row => row.target),
  ['workspace-1', 'clock', 'bluetooth', 'power'],
  'the ring walks a horizontal bar left to right'
)
assertDeepEqual(
  bar.navOrder(
    [stop('power', 0, { y: 900 }), stop('clock', 0, { y: 120 })],
    true
  ).map(row => row.target),
  ['clock', 'power'],
  'the ring walks a vertical bar top to bottom'
)

// A center module is mounted twice once an anchor is set — the drawn copy plus
// a zero-size placeholder holding its place in the flow — and both register as
// click targets. A ring stop on the placeholder would be a ring on nothing.
assertDeepEqual(
  bar.navOrder([stop('ghost', 969, { width: 0, height: 0 }), stop('clock', 969)], false)
    .map(row => row.target),
  ['clock'],
  'the ring skips a zero-size layout placeholder'
)
assertDeepEqual(
  bar.navOrder([stop('first', 40), stop('second', 40)], false).map(row => row.target),
  ['first', 'second'],
  'two stops at the same offset keep the order they registered in'
)
assertDeepEqual(bar.navOrder([], false), [], 'an empty bar has no ring')
assertDeepEqual(bar.navOrder(null, false), [], 'the ring tolerates a missing stop list')

// ----------------------------------------------------------- where it starts

// The right-hand section is where audio, network, Bluetooth, display and power
// live, which is the whole reason someone reaches for the bar without a mouse.
const ordered = bar.navOrder(scrambled, false)
assertEqual(
  ordered[bar.navStartIndex(ordered, 'right')].target,
  'bluetooth',
  'the ring starts on the first widget of the right section'
)
assertEqual(
  ordered[bar.navStartIndex(ordered, 'left')].target,
  'workspace-1',
  'the ring can be asked to start in another section'
)
assertEqual(
  bar.navStartIndex(bar.navOrder([stop('clock', 969, { region: 'center' })], false), 'right'),
  0,
  'the ring starts at the beginning when its section has nothing to focus'
)
assertEqual(bar.navStartIndex([], 'right'), -1, 'an empty ring has no starting stop')

// ------------------------------------------------------------------ stepping

assertEqual(bar.navStepIndex(4, 0, 1), 1, 'a step moves along the ring')
assertEqual(bar.navStepIndex(4, 3, 1), 0, 'the ring wraps forward off the end')
assertEqual(bar.navStepIndex(4, 0, -1), 3, 'the ring wraps backward off the start')
assertEqual(bar.navStepIndex(4, -1, 1), 0, 'stepping forward with nothing focused enters at the start')
assertEqual(bar.navStepIndex(4, -1, -1), 3, 'stepping backward with nothing focused enters at the end')
assertEqual(bar.navStepIndex(4, 9, 1), 0, 'a stale index outside the ring re-enters rather than throwing')
assertEqual(bar.navStepIndex(0, 0, 1), -1, 'an empty ring has nowhere to step')

// ------------------------------------------------------------------ the keys

// The arrow that leaves points away from the edge the bar is anchored to, so
// it is always perpendicular to the axis the ring walks. That is what keeps
// "move" and "leave" from ever being the same press — the property worth
// asserting rather than the four values.
for (const [position, leaveKey, next, prev] of [
  ['top', 'down', 'right', 'left'],
  ['bottom', 'up', 'right', 'left'],
  ['left', 'right', 'down', 'up'],
  ['right', 'left', 'down', 'up']
]) {
  assertEqual(bar.navLeaveKey(position), leaveKey, `a ${position} bar is left by pressing ${leaveKey}`)
  assertEqual(bar.navKeyRole(next, position), 'next', `a ${position} bar steps forward on ${next}`)
  assertEqual(bar.navKeyRole(prev, position), 'prev', `a ${position} bar steps back on ${prev}`)
  assertEqual(bar.navKeyRole(leaveKey, position), 'leave', `a ${position} bar leaves on ${leaveKey}`)
  assert(
    leaveKey !== next && leaveKey !== prev,
    `a ${position} bar cannot confuse leaving with moving`
  )
  // The fourth arrow points into the edge the bar is against. Nothing is there.
  const inward = { down: 'up', up: 'down', right: 'left', left: 'right' }[leaveKey]
  assertEqual(bar.navKeyRole(inward, position), '', `a ${position} bar ignores the arrow into its own edge`)
}

// Escape is the keyboard's way out and XF86Back is what a TV remote and a game
// controller send; both have to mean the same thing or the ring is a trap on
// the hardware that needs it most.
assertEqual(bar.navKeyRole('escape', 'top'), 'leave', 'Escape leaves the ring')
assertEqual(bar.navKeyRole('back', 'top'), 'leave', 'Back leaves the ring')
assertEqual(bar.navKeyRole('return', 'top'), 'activate', 'Return activates the focused widget')
assertEqual(bar.navKeyRole('space', 'top'), 'activate', 'Space activates the focused widget')
// Tab already steps between panels, so it steps between icons too and the key
// means one thing at both levels.
assertEqual(bar.navKeyRole('tab', 'top'), 'next', 'Tab steps the ring forward')
assertEqual(bar.navKeyRole('backtab', 'top'), 'prev', 'Shift-Tab steps the ring back')
assertEqual(bar.navKeyRole('q', 'top'), '', 'a key the ring has no use for is left alone')
assertEqual(bar.navKeyRole('', 'top'), '', 'the ring tolerates a key it cannot name')

// ------------------------------------------------------- the surface's shape

// The bar itself must never hold the keyboard: it is always mapped, so focusing
// it would take typing away from every application. The ring's focus lives on a
// separate surface that exists only while navigating.
assert(
  /WlrLayershell\.namespace: "omarchy-bar-nav"/.test(navSource),
  'the ring maps its own layer surface rather than focusing the bar'
)
const barPanel = barSource.slice(
  barSource.indexOf('component BarPanel:'),
  barSource.indexOf('component DragGhostPanel:')
)
assert(
  barPanel.length > 0 && !/keyboardFocus/.test(barPanel),
  'the bar surface still never takes keyboard focus'
)
assert(
  !/WlrKeyboardFocus\.(Exclusive|OnDemand)/.test(barSource),
  'no surface the bar itself maps asks for the keyboard'
)
assert(
  /visible: root\.active/.test(navSource),
  'the ring surface is mapped only while navigating'
)

// An outside agent (a controller daemon keyed on openlayer/closelayer, an
// accessibility tool) learns that the bar is being navigated from the namespace
// alone, which only works while the surface is unmapped the rest of the time.
assert(
  /WlrKeyboardFocus\.None/.test(navSource) &&
    /root\.active && !root\.yielded/.test(navSource),
  'the ring hands the keyboard to an open panel and keeps its surface mapped'
)

// Exclusive routes every pointer event compositor-wide to the surface, so the
// prime that acquires map-time focus has to settle back to OnDemand — the same
// hazard, and the same interval, as Ui/KeyboardPanel.qml.
assert(
  /WlrKeyboardFocus\.OnDemand : WlrKeyboardFocus\.Exclusive/.test(navSource),
  'the ring primes focus with Exclusive and settles on OnDemand'
)
assert(
  /interval: 75/.test(navSource),
  'the ring holds the compositor-wide pointer grab no longer than a panel does'
)

// The ring is drawn over the bar; it must not be in front of it for the mouse.
assert(
  /mask: Region \{\}/.test(navSource),
  'the ring surface takes no input, so the bar stays clickable underneath it'
)

// --------------------------------------------------- activate cannot drift

// The bar's click registry is the list of things worth focusing, and its own
// clickability filter is the one that decides what a ring can land on. A second
// list would go stale the first time a widget hid itself.
assert(
  /root\.bar\.moduleTargetClickable\(item\)/.test(navSource),
  'the ring focuses exactly what the bar says is clickable'
)
// Activating has to be the call a click makes, or pressing Return on a
// third-party widget would do something its author never wrote.
assert(
  /root\.target\.triggerPress\(button\)/.test(navSource),
  'activating the focused widget is the same call a mouse click makes'
)
assert(
  /press\(Qt\.RightButton\)/.test(barSource),
  'the ring can reach a widget right-click, which is where the verb-less actions live'
)
// Opening a panel from the ring, then tabbing to its neighbour, moves the bar
// out from under the ring.
assert(
  /function syncToPopout\(\)/.test(navSource) && /onActivePopoutChanged/.test(navSource),
  'the ring follows a panel that tabs to its neighbour'
)
// A hidden bar is parked past the screen edge; a ring on it would point at
// nothing.
assert(
  /root\.bar\.barHidden === true\) return false/.test(navSource),
  'the ring refuses to open on a hidden bar'
)

// The ring rectangle is created as a child of the focused widget rather than
// reparented onto it: a workspace button vanishes with its workspace, and a
// ring reparented onto one would be destroyed with it and never come back.
assert(
  /ringComponent\.createObject\(root\.target\)/.test(navSource),
  'the ring is created on the focused widget, so it dies with it and is rebuilt'
)

// -------------------------------------------------------------- the verbs

// `shell call <id> ...` cannot reach the bar — callIfLoaded looks in
// panelLoaders and the bar is not a panel — so the verbs live on omarchy.bar.
const barIpc = barSource.slice(barSource.indexOf('target: "omarchy.bar"'))
const barIpcBody = barIpc.slice(0, barIpc.indexOf('\n  }'))
for (const verb of [
  'navigate', 'leave', 'toggleNavigate', 'focusNext', 'focusPrev', 'activate',
  'activateSecondary', 'isNavigating'
]) {
  assert(
    new RegExp(`function ${verb}\\(\\)`).test(barIpcBody),
    `the bar exposes ${verb} over IPC`
  )
  assert(
    new RegExp(`\`omarchy.bar ${verb}\``.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).test(shellDocs) ||
      shellDocs.includes(`omarchy.bar ${verb}`),
    `omarchy-shell.md documents ${verb}`
  )
}

// The focused widget names itself. Making the ring's target count as hovered is
// what lets showTooltip and the stale-tooltip watchdog stay one path.
assert(
  /target\.tooltipHovered === true \|\| target === navTarget/.test(barSource),
  'the ring reuses the hover tooltip rather than growing a second one'
)
JS
