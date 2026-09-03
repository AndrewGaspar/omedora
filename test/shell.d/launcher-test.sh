#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const model = requireFromRoot('shell/plugins/launcher/LauncherModel.js')
const qml = fs.readFileSync(path.join(root, 'shell/plugins/launcher/Launcher.qml'), 'utf8')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'shell/plugins/launcher/manifest.json'), 'utf8'))
const bin = fs.readFileSync(path.join(root, 'bin/omarchy-launcher'), 'utf8')

// --- pins round-trip ---
assertDeepEqual(model.parsePins('a.desktop\n\nb\n a \n'), ['a', 'b'], 'pin parsing trims, strips suffix, dedupes')
assertDeepEqual(model.parsePins(''), [], 'empty pin file parses as no pins')
assertEqual(model.serializePins(['a', 'b']), 'a\nb\n', 'pins serialize one id per line')
assertEqual(model.serializePins([]), '', 'no pins serialize as empty')
assertDeepEqual(model.togglePin(['a', 'b'], 'c'), ['a', 'b', 'c'], 'toggling an unpinned app appends it')
assertDeepEqual(model.togglePin(['a', 'b'], 'a.desktop'), ['b'], 'toggling a pinned app removes it')
assertDeepEqual(model.togglePin(['a'], ''), ['a'], 'toggling an empty id is a no-op')

// --- rows: pinned-first, then alphabetical, query narrows ---
const entries = [
  { id: 'zebra', name: 'Zebra', subtext: '' },
  { id: 'alpha', name: 'Alpha', subtext: '' },
  { id: 'mike', name: 'Mike', subtext: 'IRC client' },
]
assertDeepEqual(
  model.buildRows(entries, ['mike'], '').map(r => r.appId),
  ['mike', 'alpha', 'zebra'],
  'pinned apps sort first in pin order, rest alphabetical'
)
assert(
  model.buildRows(entries, ['mike'], '')[0].pinned === true,
  'pinned row carries the pinned flag'
)
assertDeepEqual(
  model.buildRows(entries, [], 'irc').map(r => r.appId),
  ['mike'],
  'query matches subtext'
)
assertDeepEqual(
  model.buildRows(entries, [], 'ALP').map(r => r.appId),
  ['alpha'],
  'query matching is case-insensitive'
)
assertDeepEqual(model.buildRows(entries, [], 'nope'), [], 'query with no matches returns no rows')

// --- paging math ---
assertEqual(model.pageCount(0, 6), 1, 'empty list still counts one page')
assertEqual(model.pageCount(10, 6), 2, 'ten tiles at six per page need two pages')
assertEqual(model.clampPage(9, 10, 6), 1, 'page clamps to the last page')

// --- D-pad movement on 10 tiles, 3 columns, 6 per page ---
// page 0: 0 1 2 / 3 4 5   page 1: 6 7 8 / 9
let s = model.moveCursor(0, 0, 10, 3, 6, 'Right')
assertDeepEqual([s.page, s.index], [0, 1], 'right moves within the row')
s = model.moveCursor(0, 2, 10, 3, 6, 'Right')
assertDeepEqual([s.page, s.index], [1, 6], 'right at the row edge turns to the next page same row')
s = model.moveCursor(1, 6, 10, 3, 6, 'Down')
assertDeepEqual([s.page, s.index], [1, 9], 'down moves within the column')
s = model.moveCursor(1, 9, 10, 3, 6, 'Left')
assertDeepEqual([s.page, s.index], [0, 5], 'left at the row edge turns to the previous page same row')
s = model.moveCursor(0, 5, 10, 3, 6, 'Up')
assertDeepEqual([s.page, s.index], [0, 2], 'up moves within the column')
s = model.moveCursor(0, 2, 10, 3, 6, 'Down')
assertDeepEqual([s.page, s.index], [0, 5], 'down moves within the column')
s = model.moveCursor(0, 5, 10, 3, 6, 'Down')
assertDeepEqual([s.page, s.index], [1, 8], 'down past the page bottom turns to the next page same column')
s = model.moveCursor(0, 0, 10, 3, 6, 'Left')
assertDeepEqual([s.page, s.index], [0, 0], 'left at the grid start stays put')
s = model.moveCursor(0, 0, 10, 3, 6, 'Up')
assertDeepEqual([s.page, s.index], [0, 0], 'up at the grid start stays put')
s = model.moveCursor(1, 9, 10, 3, 6, 'Down')
assertDeepEqual([s.page, s.index], [1, 9], 'down at the grid end stays put')
s = model.moveCursor(1, 9, 10, 3, 6, 'Right')
assertDeepEqual([s.page, s.index], [1, 9], 'right at the grid end stays put')
s = model.moveCursor(0, 1, 10, 3, 6, 'Up')
assertDeepEqual([s.page, s.index], [0, 1], 'up on the first row stays put')
s = model.moveCursor(0, 0, 0, 3, 6, 'Right')
assertDeepEqual([s.page, s.index], [0, 0], 'movement on an empty list is a no-op')

// --- plugin contract ---
assertEqual(manifest.id, 'omarchy.launcher', 'manifest carries the launcher plugin id')
assert(manifest.kinds.includes('overlay'), 'launcher is an overlay plugin')
assertEqual(manifest.entryPoints.overlay, 'Launcher.qml', 'overlay entry point is Launcher.qml')
assert(/function open\(payloadJson\) \{[\s\S]*?\n  \}/.test(qml), 'launcher implements open(payloadJson)')
assert(/function close\(\) \{[\s\S]*?\n  \}/.test(qml), 'launcher implements close()')
assert(/function ping\(\) \{ return "ok" \}/.test(qml), 'launcher implements ping()')
assert(qml.includes('root.appLibrary.launch('), 'launcher launches through the shared app library')
assert(qml.includes('root.appLibrary.iconSource('), 'launcher resolves icons through the shared app library')
assert(qml.includes('LauncherModel.moveCursor('), 'launcher delegates 2D movement to the tested model')
assert(qml.includes('WlrLayershell.namespace: "omarchy-launcher"'), 'launcher owns its layershell namespace')
assert(qml.includes('WlrLayershell.layer: WlrLayer.Overlay'), 'launcher renders on the overlay layer')
assert(qml.includes('Qt.Key_PageUp') && qml.includes('Qt.Key_PageDown'), 'launcher turns pages on PageUp/PageDown')
assert(qml.includes('Qt.Key_Home') && qml.includes('Qt.Key_End'), 'launcher jumps on Home/End')
assert(qml.includes('launcher-pins'), 'launcher persists pins under the user config dir')
assert(qml.includes('hoverTile(globalIndex)'), 'launcher selects tiles on mouse hover without rebuilding mid-signal')
assert(qml.includes('onPositionChanged: root.hoverTile(globalIndex)'), 'launcher hover follows real pointer motion, not delegate recreation')
assert(/function hoverTile\(globalIndex\) \{[\s\S]*?Math\.min\(Math\.max\(0, globalIndex\), root\.rows\.length - 1\)[\s\S]*?\n  \}/.test(qml), 'launcher hover clamps recycled delegate indexes to the live rows')
assert(/onClicked: \{[\s\S]*?root\.activateSelected\(\)[\s\S]*?\n {14}\}/.test(qml), 'launcher tile click launches through the shared activate path')
assert(qml.includes('property bool iconFailed'), 'launcher falls back to a generic glyph for stale icon files')

// --- bin wrapper contract ---
assert(bin.includes('# omarchy:summary='), 'launcher command declares CLI metadata')
assert(bin.includes('omarchy-shell shell toggle omarchy.launcher'), 'launcher toggle routes to the plugin')
assert(bin.includes('omarchy-shell shell summon omarchy.launcher'), 'launcher summon routes to the plugin')
assert(bin.includes('omarchy-shell shell hide omarchy.launcher'), 'launcher close routes to the plugin')
JS
