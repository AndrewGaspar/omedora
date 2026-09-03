// Pure application-grid logic for the omarchy.launcher overlay.
//
// Everything here is framework-free so the shell test suite can require it
// under node: rows (pinned-first ordering), paging, 2D cursor movement with
// edge page-turns, and pin-file parsing. Launcher.qml delegates to these and
// only owns the visuals, the app-library wiring, and the pin persistence.
function normalizeId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

// One desktop id per line; blank lines and repeats are dropped, order kept.
function parsePins(raw) {
  var out = []
  var seen = ({})
  var lines = String(raw || "").split(/\n/)
  for (var i = 0; i < lines.length; i++) {
    var id = normalizeId(lines[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function serializePins(pins) {
  var clean = parsePins((pins || []).join("\n"))
  return clean.length > 0 ? clean.join("\n") + "\n" : ""
}

function togglePin(pins, id) {
  var target = normalizeId(id)
  var current = parsePins((pins || []).join("\n"))
  if (!target) return current
  var out = []
  var found = false
  for (var i = 0; i < current.length; i++) {
    if (current[i] === target) found = true
    else out.push(current[i])
  }
  if (!found) out.push(target)
  return out
}

// Entries are { id, name, subtext }. Pinned ids come first in pin order;
// everything else sorts alphabetically (case-insensitive). A query narrows
// by substring over name, subtext, and id.
function buildRows(entries, pins, query) {
  var list = Array.isArray(entries) ? entries : []
  var order = parsePins((pins || []).join("\n"))
  var rank = ({})
  for (var r = 0; r < order.length; r++) rank[order[r]] = r

  var needle = String(query || "").toLowerCase().trim()
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var id = normalizeId(entry.id)
    if (!id) continue
    var name = String(entry.name || id)
    var haystack = [name, entry.subtext, id].join(" ").toLowerCase()
    if (needle && haystack.indexOf(needle) < 0) continue
    rows.push({
      appId: id,
      label: name,
      subtext: String(entry.subtext || ""),
      icon: String(entry.icon || ""),
      pinned: rank[id] !== undefined,
      pinRank: rank[id] !== undefined ? rank[id] : -1
    })
  }

  rows.sort(function(a, b) {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
    if (a.pinned && b.pinned) return a.pinRank - b.pinRank
    var an = a.label.toLowerCase()
    var bn = b.label.toLowerCase()
    if (an < bn) return -1
    if (an > bn) return 1
    return 0
  })
  return rows
}

function pageCount(total, perPage) {
  var n = Math.max(0, total | 0)
  var size = Math.max(1, perPage | 0)
  if (n === 0) return 1
  return Math.floor((n + size - 1) / size)
}

function clampPage(page, total, perPage) {
  var count = pageCount(total, perPage)
  var p = page | 0
  if (p < 0) return 0
  if (p >= count) return count - 1
  return p
}

// Index of the last tile on the given page (clamped to the row count).
function lastIndexOnPage(page, total, perPage) {
  var size = Math.max(1, perPage | 0)
  var last = (page | 0) * size + size - 1
  return Math.min(Math.max(0, total | 0) - 1, last)
}

// D-pad movement across a paged grid. Position is (page, index); moving past
// an edge turns the page and lands on the same row/column when one exists,
// otherwise on the nearest tile. Returns { page, index }.
function moveCursor(page, index, total, columns, perPage, key) {
  var n = Math.max(0, total | 0)
  var cols = Math.max(1, columns | 0)
  var size = Math.max(1, perPage | 0)
  if (n === 0) return { page: 0, index: 0 }

  var p = clampPage(page, n, size)
  var start = p * size
  // A filtered list can leave the cursor on another page; rebase it onto
  // this page's first tile before moving.
  var current = Math.min(Math.max(0, index | 0), n - 1)
  if (current < start || current > start + size - 1) current = start
  var col = (current - start) % cols
  var row = Math.floor((current - start) / cols)
  var rows = Math.max(1, Math.ceil(size / cols))
  var count = pageCount(n, size)

  function land(nextPage, nextCol, nextRow) {
    var np = Math.min(Math.max(0, nextPage), count - 1)
    var ns = np * size
    var pageLast = lastIndexOnPage(np, n, size)
    // Rows on a short final page may not have this column; slide left.
    var c = Math.min(nextCol, cols - 1)
    var r = Math.min(Math.max(0, nextRow), rows - 1)
    while (r >= 0 && ns + r * cols + c > pageLast) {
      if (c > 0) c--
      else r--
    }
    if (r < 0) return { page: np, index: ns }
    var at = ns + r * cols + c
    if (at > pageLast) at = pageLast
    return { page: np, index: at }
  }

  if (key === "Left") {
    if (col > 0) return { page: p, index: current - 1 }
    if (p > 0) return land(p - 1, cols - 1, row)
    return { page: p, index: current }
  }
  if (key === "Right") {
    if (current + 1 <= start + size - 1 && current + 1 < n && col < cols - 1) return { page: p, index: current + 1 }
    if (p < count - 1) return land(p + 1, 0, row)
    return { page: p, index: current }
  }
  if (key === "Up") {
    if (row > 0) return { page: p, index: Math.max(start, current - cols) }
    if (p > 0) return land(p - 1, col, rows - 1)
    return { page: p, index: current }
  }
  if (key === "Down") {
    var below = current + cols
    if (below <= start + size - 1 && below < n) return { page: p, index: below }
    if (p < count - 1) return land(p + 1, col, 0)
    return { page: p, index: current }
  }
  return { page: p, index: current }
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeId: normalizeId,
    parsePins: parsePins,
    serializePins: serializePins,
    togglePin: togglePin,
    buildRows: buildRows,
    pageCount: pageCount,
    clampPage: clampPage,
    lastIndexOnPage: lastIndexOnPage,
    moveCursor: moveCursor
  }
}
