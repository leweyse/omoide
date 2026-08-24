// Pure helpers for the QML side. No Qt types in here on purpose: the same file
// is required by node for unit tests, which is the convention every *Model.js
// in the Omarchy shell follows.
//
// Time formatting lives here and nowhere else, so the to-do inside a memory and
// the same to-do in the archive can never disagree about how a date reads.

function pad(value) {
  return String(value).length < 2 ? "0" + value : String(value)
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function parseDate(iso) {
  if (!iso) return null
  var parsed = new Date(iso)
  return isNaN(parsed.getTime()) ? null : parsed
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear()
      && a.getMonth() === b.getMonth()
      && a.getDate() === b.getDate()
}

function dayOffset(target, reference) {
  var a = new Date(target.getFullYear(), target.getMonth(), target.getDate())
  var b = new Date(reference.getFullYear(), reference.getMonth(), reference.getDate())
  return Math.round((a - b) / 86400000)
}

// "12:30 today", "14:30 tomorrow", "18:30 22 Dec" -- the reference's phrasing.
function formatWhen(iso, now) {
  var when = parseDate(iso)
  if (!when) return ""
  var reference = now ? new Date(now) : new Date()
  var clock = pad(when.getHours()) + ":" + pad(when.getMinutes())
  var offset = dayOffset(when, reference)
  if (offset === 0) return clock + " today"
  if (offset === 1) return clock + " tomorrow"
  if (offset === -1) return clock + " yesterday"
  var stamp = clock + " " + when.getDate() + " " + MONTHS[when.getMonth()]
  return when.getFullYear() === reference.getFullYear()
       ? stamp : stamp + " " + when.getFullYear()
}

// A compact badge for event cards: { top: "DEC", bottom: "19" }.
function dateBadge(iso) {
  var when = parseDate(iso)
  if (!when) return { top: "", bottom: "" }
  return { top: MONTHS[when.getMonth()].toUpperCase(), bottom: String(when.getDate()) }
}

// "Friday 19 December, 18:00 - 21:00"
function formatRange(startIso, endIso, allDay) {
  var start = parseDate(startIso)
  if (!start) return ""
  var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  var full = ["January", "February", "March", "April", "May", "June", "July",
              "August", "September", "October", "November", "December"]
  var head = days[start.getDay()] + " " + start.getDate() + " " + full[start.getMonth()]
  if (allDay) return head
  var text = head + ", " + pad(start.getHours()) + ":" + pad(start.getMinutes())
  var end = parseDate(endIso)
  if (end) {
    text += " - " + pad(end.getHours()) + ":" + pad(end.getMinutes())
  }
  return text
}

// Which archive group a to-do belongs in.
//
// Derived from the item's own due date and completion ONLY. A reminder that
// already fired says nothing about whether the to-do is done, so an overdue
// item stays in "past" until it is checked off rather than disappearing the
// moment its notification arrived.
function archiveGroup(todo, now) {
  if (!todo) return "anytime"
  if (todo.completedAt) return "completed"
  var due = parseDate(todo.dueAt)
  if (!due) return "anytime"
  return due.getTime() >= (now ? new Date(now).getTime() : Date.now())
       ? "upcoming" : "past"
}

// The digest line. Computed, never generated: it is arithmetic, and it has to
// read identically every time.
function digestLine(digest) {
  var events = (digest && digest.events) || 0
  var todos = (digest && digest.todos) || 0
  if (!events && !todos) return "Nothing scheduled today."
  var parts = []
  if (events) parts.push(events + " event" + (events === 1 ? "" : "s"))
  if (todos) parts.push(todos + " task" + (todos === 1 ? "" : "s"))
  return "You have " + parts.join(" and ") + " today."
}

// Assign items to the shortest column. QML has no masonry layout, and a naive
// round-robin leaves ragged columns once thumbnails vary in height.
// Where a list cursor lands after one arrow press.
//
// `cursor` of -1 means nothing is focused yet: the first press enters at the top
// going down and at the bottom going up, rather than at whichever end -1 + d
// happens to fall on. Returns null when the press should be left alone -- an
// empty list, or an arrow already at the end -- so the caller can hand the key
// back for something else to use. That is what lets Left at the first Tasks tab
// fall through to the sidebar instead of being swallowed.
function stepList(count, cursor, d) {
  if (!count || count < 1) return null
  if (d === 0) return null
  // Out of range as well as unset: a cursor left over from a longer list must
  // re-enter rather than hand the key away, or a stale index would silently
  // bounce the user out to the sidebar.
  if (cursor < 0 || cursor >= count) return d > 0 ? 0 : count - 1
  var next = cursor + d
  if (next < 0 || next >= count) return null
  return next
}

// Where the grid cursor lands after one arrow key.
//
// `buckets` is column-major, the shape MasonryGrid already builds, so a card's
// column and row are known exactly rather than guessed from a flat index.
// Returns null to mean "I did not use this key", which is what lets Left at the
// first column fall through to the sidebar.
//
// Three rules that are easy to get wrong, all covered by tests:
//   - a first press with no cursor enters at the top of the first non-empty
//     column, whichever direction it was
//   - sideways into a shorter column clamps to that column's last row, so the
//     cursor can never fall out of the grid
//   - sideways over an empty column steps past it instead of stalling on it
function stepGrid(buckets, cursorId, dx, dy) {
  if (!buckets || !buckets.length) return null

  var col = -1
  var row = -1
  for (var c = 0; c < buckets.length; c++) {
    var column = buckets[c] || []
    for (var r = 0; r < column.length; r++)
      if (column[r] && column[r].id === cursorId) { col = c; row = r }
  }

  if (col < 0) {
    for (var c2 = 0; c2 < buckets.length; c2++)
      if ((buckets[c2] || []).length) return buckets[c2][0].id
    return null
  }

  if (dx !== 0) {
    var next = col + dx
    while (next >= 0 && next < buckets.length && !(buckets[next] || []).length)
      next += dx
    if (next < 0 || next >= buckets.length) return null
    var target = buckets[next]
    return target[Math.min(row, target.length - 1)].id
  }

  if (dy !== 0) {
    var r2 = row + dy
    if (r2 < 0 || r2 >= buckets[col].length) return null
    return buckets[col][r2].id
  }

  return null
}

// Which grid column a horizontal position belongs to, for crossing DOWN out of
// the collections row into the grid. Landing on the first card would ignore
// where you already were; landing under your finger is what the eye expects.
//
// `x` is the centre of the tile you are leaving, in the grid's own coordinates.
function columnAt(x, columnCount, columnWidth, gap) {
  if (!columnCount || columnCount < 1) return 0
  var stride = columnWidth + (gap || 0)
  if (stride <= 0) return 0
  var i = Math.floor(x / stride)
  return Math.max(0, Math.min(columnCount - 1, i))
}

// The CLI verb for acting on a to-do row from the keyboard, or null when the row
// cannot be acted on.
//
// Three pages show these rows -- Tasks, For you, and a memory's to-dos card --
// and each has the row as plain data rather than as a delegate it can call a
// method on. Deciding here keeps one answer to "what does Space do to this row"
// instead of three that can drift.
//
// A suggestion has nothing to complete: it is the agent's proposal, so acting on
// it accepts it. Anything else toggles.
function todoAction(row) {
  if (!row || !row.id) return null
  if (row.status === "suggested") return ["item", "promote", "--id", row.id]
  return ["item", row.completedAt ? "reopen" : "complete", "--id", row.id]
}

function balanceColumns(items, columnCount, heightOf) {
  var columns = []
  var heights = []
  for (var c = 0; c < columnCount; c++) { columns.push([]); heights.push(0) }
  for (var i = 0; i < (items || []).length; i++) {
    var shortest = 0
    for (var j = 1; j < columnCount; j++) {
      if (heights[j] < heights[shortest]) shortest = j
    }
    columns[shortest].push(items[i])
    heights[shortest] += heightOf ? heightOf(items[i]) : 1
  }
  return columns
}

// A block whose type this build does not know renders as nothing rather than
// erroring, so a memory written by a newer version of the plugin still opens.
var KNOWN_BLOCKS = ["source", "image", "note", "summary", "list",
                    "event", "todos", "text", "quote", "code"]

function isRenderable(type) {
  return KNOWN_BLOCKS.indexOf(type) !== -1
}

// An ISO timestamp split into the two fields the editor shows, in LOCAL time
// and day-first. Stored timestamps are UTC, so slicing the string would show
// the wrong clock time to anyone not on UTC.
function dateParts(iso) {
  var parsed = parseDate(iso)
  if (!parsed) return { date: "", time: "" }
  var pad = function (n) { return (n < 10 ? "0" : "") + n }
  return {
    date: pad(parsed.getDate()) + "/" + pad(parsed.getMonth() + 1)
          + "/" + parsed.getFullYear(),
    time: pad(parsed.getHours()) + ":" + pad(parsed.getMinutes())
  }
}

// DD/MM/YYYY plus HH:MM into the "YYYY-MM-DD HH:MM" the CLI parses, or "" when
// either half is incomplete or out of range.
//
// Returning "" rather than a best guess is the point: a half-typed row is
// ignored on save instead of being stored as some other date. The ISO result
// also sorts lexicographically, which is how the earliest reminder is found
// without parsing anything back.
function toCliWhen(date, time) {
  var d = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(String(date || ""))
  var t = /^(\d{2}):(\d{2})$/.exec(String(time || ""))
  if (!d || !t) return ""
  if (+d[2] < 1 || +d[2] > 12 || +d[1] < 1 || +d[1] > 31) return ""
  if (+t[1] > 23 || +t[2] > 59) return ""
  return d[3] + "-" + d[2] + "-" + d[1] + " " + t[1] + ":" + t[2]
}

// A loose stem for matching a tag against a collection name, so a "concert"
// tag finds a "Concerts" collection. Only a trailing plural s, and only on
// words long enough that the s is not part of the word ("css", "ios").
function collectionStem(text) {
  var value = String(text || "").toLowerCase().trim()
  return value.length > 3 && value.charAt(value.length - 1) === "s"
         ? value.slice(0, -1) : value
}

// Collections a memory looks like it belongs in: its tags matched against the
// names that already exist, minus the ones it is already in.
//
// Pure on purpose -- tags in, names out -- so the matching rule is testable
// without a running shell, and so nothing here can write anything.
function suggestCollections(tags, allNames, currentNames) {
  var wanted = {}, already = {}, out = []
  var i
  for (i = 0; i < (tags || []).length; i++)
    wanted[collectionStem(tags[i])] = true
  for (i = 0; i < (currentNames || []).length; i++)
    already[collectionStem(currentNames[i])] = true
  for (i = 0; i < (allNames || []).length; i++) {
    var key = collectionStem(allNames[i])
    if (wanted[key] && !already[key] && out.indexOf(allNames[i]) < 0)
      out.push(allNames[i])
  }
  return out
}

// An alarm's lead time in words: "30 minutes before", "1 hour before". Picks
// the largest unit that divides cleanly, so -1440 reads as a day rather than
// 1440 minutes.
function formatLead(offsetMin) {
  if (offsetMin === null || offsetMin === undefined) return ""
  var value = Number(offsetMin)
  if (!isFinite(value)) return ""
  var mins = Math.abs(value)
  if (mins === 0) return "at the time"
  var unit, count
  if (mins % 1440 === 0) { count = mins / 1440; unit = "day" }
  else if (mins % 60 === 0) { count = mins / 60; unit = "hour" }
  else { count = mins; unit = "minute" }
  return count + " " + unit + (count === 1 ? "" : "s")
         + (value > 0 ? " after" : " before")
}

// One reminder as a line of text. A relative alarm reads as a lead time, an
// absolute one as a date -- the same row can be either.
function reminderLine(reminder) {
  if (!reminder) return ""
  var lead = formatLead(reminder.offsetMin)
  if (lead.length) return "Reminder " + lead
  var when = formatWhen(reminder.fireAt)
  return when.length ? "Reminder " + when : ""
}

// A list block's items as editable lines, and back. "Label: text" round-trips
// as a labelled pair; a bare line is a plain bullet.
//
// A line becomes a labelled pair only when what precedes the first colon looks
// like a label: at most four words, no comma, not ending in a digit, and not
// followed by a slash. The last two are what stop real text being mangled --
// "Doors open at 19:15 and support at 20:00" would split at the clock, and
// "See https://deroma.be" would split at the URL scheme.
function itemsToLines(items) {
  var out = []
  for (var i = 0; i < (items || []).length; i++) {
    var entry = items[i] || {}
    var label = String(entry.label || "").trim()
    var text = String(entry.text || "").trim()
    out.push(label.length ? label + ": " + text : text)
  }
  return out.join("\n")
}

function linesToItems(body) {
  var lines = String(body || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line.length) continue
    var cut = line.indexOf(":")
    var label = cut > 0 ? line.slice(0, cut).trim() : ""
    var looksLikeLabel = label.length > 0
                         && label.length <= 32
                         && label.indexOf(",") < 0
                         && label.split(/\s+/).length <= 4
                         && !/[0-9]$/.test(label)
                         && line.charAt(cut + 1) !== "/"
    if (looksLikeLabel) {
      out.push({ label: label, text: line.slice(cut + 1).trim() })
    } else {
      out.push({ label: "", text: line })
    }
  }
  return out
}

// Qt's Text defaults to AutoText, which sniffs its input for markup and renders
// it as rich text -- and rich text loads <img src> over the network. Everything
// a block carries is derived from whatever was on screen when the capture was
// taken, so it is untrusted: a caption that says <img src="http://host/?x"> is a
// request off this machine, made by the desktop, on open.
//
// Fields that need no markup set textFormat: Text.PlainText at the binding,
// which is the cheaper guarantee. This exists for the one place that does want
// markup of its own -- a list item's bold label -- where the model's text has to
// survive being concatenated into a StyledText string.
function escapeMarkup(text) {
  return String(text === null || text === undefined ? "" : text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

function truncate(text, limit) {
  var value = String(text || "")
  return value.length <= limit ? value : value.slice(0, limit - 1) + "…"
}

if (typeof module !== "undefined") {
  module.exports = {
    formatWhen: formatWhen,
    dateBadge: dateBadge,
    formatRange: formatRange,
    archiveGroup: archiveGroup,
    digestLine: digestLine,
    balanceColumns: balanceColumns,
    stepList: stepList,
    todoAction: todoAction,
    stepGrid: stepGrid,
    columnAt: columnAt,
    isRenderable: isRenderable,
    truncate: truncate,
    escapeMarkup: escapeMarkup,
    itemsToLines: itemsToLines,
    linesToItems: linesToItems,
    formatLead: formatLead,
    reminderLine: reminderLine,
    collectionStem: collectionStem,
    suggestCollections: suggestCollections,
    parseDate: parseDate,
    dateParts: dateParts,
    toCliWhen: toCliWhen,
    sameDay: sameDay
  }
}
