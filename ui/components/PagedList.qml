import QtQuick

// Rows a page at a time, from any CLI read that answers with `pageInfo` and
// resumes from its `endCursor`: `list` and `search` for memory cards,
// `archive --group` for to-dos, `events` for the carousel.
//
// Non-visual: a view owns one, points `args` at the query it shows, and binds
// to `rows`. Only the latest request is ever applied, so a chip or tab switched
// mid-load never lands the previous one's page.
QtObject {
  id: root

  property var service: null
  // The query without paging, such as ["list"], ["search", "--q", text],
  // ["archive", "--group", "open"] or ["events"]. An empty list shows nothing
  // and asks for nothing.
  property var args: []
  // The key the rows arrive under. `list` answers under `memories`, `search`
  // under `results`, `archive` under `items` and `events` under `events`.
  property string listKey: "memories"
  // A chip id, "" for none.
  property string facet: ""
  // Cards per request; the page sizes it to fill its viewport and then some.
  property int pageSize: 24

  property var rows: []
  property int total: 0
  property bool hasNextPage: false
  property bool loading: false
  // Loading cards that are not on screen yet: a first page, or the next one.
  // A re-fetch of what is already shown does not count, so an edit elsewhere
  // never flashes placeholders over cards that are already there.
  readonly property bool fetchingNew: root.loading && (!root.loaded || root.appending)
  property bool appending: false
  // True once the first page for the current query has answered.
  property bool loaded: false
  property string endCursor: ""

  property int token: 0

  // A changed query starts over, once its bindings have settled: a page that
  // reloaded from its own change handler would read the previous chip or
  // query, and a search and a chip changing together cost one reload, not two.
  // A timer rather than Qt.callLater, because it dies with this object: a
  // view replaced the moment it was created must not reload after it is gone.
  property Timer settle: Timer {
    interval: 0
    onTriggered: root.reload()
  }
  onArgsChanged: root.settle.restart()
  onFacetChanged: root.settle.restart()
  Component.onCompleted: root.settle.restart()

  function query(extra) {
    var command = root.args.slice()
    if (root.facet.length)
      command = command.concat(["--facet", root.facet])
    return command.concat(extra)
  }

  // A fresh first page, for a new query or chip.
  function reload() {
    root.token++
    root.rows = []
    root.total = 0
    root.hasNextPage = false
    root.endCursor = ""
    root.loaded = false
    if (!root.service || !root.args.length) {
      root.loading = false
      return
    }
    root.fetch(root.pageSize, "", false)
  }

  // The next page, if there is one and nothing is on its way.
  function loadMore() {
    if (!root.service || !root.loaded || root.loading || !root.hasNextPage)
      return
    root.fetch(root.pageSize, root.endCursor, true)
  }

  // After the library changed: everything already on screen again, from the
  // top, so an edit shows up without the view losing its place.
  function refreshLoaded() {
    if (!root.service || !root.args.length) return
    root.token++
    root.fetch(Math.max(root.pageSize, root.rows.length), "", false)
  }

  function fetch(limit, after, append) {
    var mine = ++root.token
    var extra = ["--limit", String(limit)]
    if (after.length) extra = extra.concat(["--after", after])
    root.loading = true
    root.appending = append
    root.service.call(root.query(extra), function (code, json) {
      // The page may have been unloaded while the request was out.
      if (!root || mine !== root.token) return
      root.loading = false
      root.appending = false
      if (code !== 0 || !json) return
      var page = json[root.listKey] || []
      var info = json.pageInfo || {}
      root.rows = append ? root.rows.concat(page) : page
      root.total = info.total || 0
      root.hasNextPage = info.hasNextPage === true
      root.endCursor = info.endCursor || ""
      root.loaded = true
    })
  }
}
