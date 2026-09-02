#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const defaultMenuJsonc = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')

// App rows the way Menu.qml's mergeAppRows() builds them: the id is "apps."
// plus the desktop-file stem, the description is GenericName, and the aliases
// are GenericName followed by Keywords.
function appRow(label, appId, genericName, keywords) {
  return {
    id: 'apps.' + appId,
    parent: 'apps',
    kind: 'app',
    appId: appId,
    label: label,
    description: genericName,
    aliases: (genericName ? [genericName] : []).concat(keywords || []),
    order: 0
  }
}

const apps = [
  appRow('Google Chrome', 'google-chrome', 'Web Browser', []),
  appRow('Chromium', 'chromium', 'Web Browser', ['browser']),
  appRow('Spotify', 'spotify', 'Music Player', ['music', 'player']),
  appRow('Alacritty', 'Alacritty', 'Terminal', ['terminal']),
  appRow('Ghostty', 'com.mitchellh.ghostty', 'Terminal Emulator', []),
  appRow('Node.js', 'nodejs', '', []),
  appRow('btop++', 'btop', 'System Monitor', ['system', 'process', 'task']),
  appRow('Telegram Desktop', 'org.telegram.desktop', 'Chat', ['messenger']),
  appRow('Files', 'org.gnome.Nautilus', 'File Manager', []),
  appRow('Xournal++', 'com.github.xournalpp.xournalpp', 'Notetaking', [])
]

function found(query) {
  return apps
    .filter(entry => menu.matchesQuery(entry, query, true))
    .sort((a, b) => {
      const byScore = menu.searchScore({}, a, query) - menu.searchScore({}, b, query)
      return byScore !== 0 ? byScore : a.label.localeCompare(b.label)
    })
    .map(entry => entry.label)
}

// Dictation arrives as a sentence, because that is what a speech model emits:
// sentence case, a trailing period, and the words a person says around a name.
// Every one of these found nothing before the query was normalized.
assertDeepEqual(found('Chrome.'), ['Google Chrome'], 'search ignores a dictated trailing period')
assertDeepEqual(found('Spotify.'), ['Spotify'], 'search ignores a trailing period on an exact name')
assertDeepEqual(found('Open Spotify.'), ['Spotify'], 'search ignores a leading "open"')
assertDeepEqual(found('Open Chrome, please.'), ['Google Chrome'], 'search ignores "please" and an interior comma')
assertDeepEqual(found('Open the browser.'), ['Chromium', 'Google Chrome'], 'search ignores "open" and "the" and still reaches GenericName')
assertDeepEqual(found('Music.'), ['Spotify'], 'search reaches a keyword through a dictated period')
assertDeepEqual(found('Terminal.'), ['Alacritty', 'Ghostty'], 'search reaches every terminal through a dictated period')
assertDeepEqual(found('gogle chrome'), ['Google Chrome'], 'search tolerates a mishearing as a subsequence of the name')

// The stock matcher took the leaf of a dotted id, which for an app row is the
// desktop-file stem: org.telegram.desktop searched as the literal word
// "desktop", and org.gnome.Nautilus lost its vendor prefix entirely.
assertDeepEqual(found('desktop'), ['Telegram Desktop'], 'an app id ending in .desktop is not searchable as the bare word "desktop"')
assertDeepEqual(found('org.telegram.desktop'), ['Telegram Desktop'], 'an app is searchable by its whole desktop-file stem')
assertDeepEqual(found('nautilus'), ['Files'], 'an app is searchable by a stem its label never mentions')
assertDeepEqual(found('google-chrome'), ['Google Chrome'], 'an app is searchable by its hyphenated stem')

// The stock matcher folded `._-` for ids and aliases but never for the label,
// so a name whose punctuation is load-bearing only matched spelled its way.
assertDeepEqual(found('nodejs'), ['Node.js'], 'a label folds its punctuation for matching')
assertDeepEqual(found('node.js'), ['Node.js'], 'a label still matches spelled with its punctuation')
assertDeepEqual(found('node js'), ['Node.js'], 'a label still matches spelled with a space')
assertDeepEqual(found('xournal'), ['Xournal++'], 'a label matches without its trailing punctuation')

// Regressions: what a keyboard user types must land exactly where it did.
assertDeepEqual(found('chrome'), ['Google Chrome'], 'a plain app name still matches only that app')
assertDeepEqual(found('btop++'), ['btop++'], 'punctuation inside a label survives in the corpus')
assertDeepEqual(found('btop'), ['btop++'], 'a label is still found without its punctuation')
assertDeepEqual(found('browser'), ['Chromium', 'Google Chrome'], 'GenericName matching is unchanged')
assertDeepEqual(found('Web Browser'), ['Chromium', 'Google Chrome'], 'a multi-word GenericName is unchanged')

// A query that normalizes away to nothing is someone typing a stray character,
// not someone dictating a name. It must keep filtering rather than list every
// row, which is what an empty term list would do.
assertDeepEqual(found('.'), [], 'a lone period matches nothing rather than everything')
assertEqual(found('the').length, 0, 'a lone filler word does not become an empty query that matches everything')

// Ranking: a subsequence is the weakest thing the matcher accepts, so it never
// climbs over a name that matched literally.
const ranked = [appRow('Ghostty', 'com.mitchellh.ghostty', 'Terminal Emulator', []), appRow('Go', 'go', 'Programming', [])]
assert(
  menu.searchScore({}, ranked[0], 'ghostty') < menu.searchScore({}, ranked[1], 'ghostty'),
  'an exact name outranks a row that only matches as a subsequence'
)

// Drilldown search over the real menu is untouched: same rows, same order.
const defaultItems = menu.parseMenuJsonc(defaultMenuJsonc)
const defaultMenu = menu.mergeMenuSources(defaultItems, [])
function menuHits(query) {
  return defaultMenu.itemOrder
    .map(id => defaultMenu.items[id])
    .filter(entry => entry && menu.matchesQuery(entry, query, true))
    .sort((a, b) => menu.searchScore(defaultMenu.items, a, query) - menu.searchScore(defaultMenu.items, b, query))
    .map(entry => entry.id)
}
assertDeepEqual(
  menuHits('theme'),
  ['style.theme', 'install.style.theme', 'remove.theme', 'update.themes'],
  'menu drilldown search reaches the same theme rows in the same order'
)
assertDeepEqual(menuHits('style'), ['install.style', 'style'], 'menu drilldown search reaches the same style rows in the same order')

// The normalizer lives on the matching side only. filterText is what the
// search field shows and what dmenu hands back as the answer, so a dictated
// period has to survive in it even though the matcher ignores it.
assert(
  menuQml.includes('root.setFilter(root.filterText + event.text)'),
  'typed and dictated characters still land in filterText verbatim'
)
assert(
  menuQml.includes('root.applyDmenuSelection(root.filterText)'),
  'dmenu still returns filterText verbatim rather than a normalized query'
)

// The terms themselves, so a failure points at the normalizer rather than at a
// fixture.
assertDeepEqual(menu.searchTerms('Open Chrome, please.'), ['chrome'], 'normalizer drops filler words and sentence punctuation')
assertDeepEqual(menu.searchTerms('Node.js'), ['node', 'js'], 'normalizer folds interior punctuation to term boundaries')
assertDeepEqual(menu.searchTerms('open'), ['open'], 'normalizer keeps a filler word that is the whole query')
assertDeepEqual(menu.searchTerms('.'), ['.'], 'normalizer keeps a query that is nothing but punctuation')
assertDeepEqual(menu.searchTerms(''), [], 'normalizer leaves an empty query empty')
assert(menu.subsequenceMatch('gogle', 'google chrome'), 'subsequence matching finds a dropped letter')
assert(!menu.subsequenceMatch('gc', 'google chrome'), 'subsequence matching ignores terms under three characters')
assert(!menu.subsequenceMatch('theme', 'virtual machine manager'), 'subsequence matching is anchored to a word start')
JS
