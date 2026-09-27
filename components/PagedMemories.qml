import QtQuick

// Memory cards a page at a time, from `list` or `search`, which both answer
// with `pageInfo` and resume from its `endCursor`.
//
// Non-visual: a page owns one, points `args` at the query it shows, and binds
// its grid to `memories`. Only the latest request is ever applied, so a chip
// switched mid-load never lands the previous chip's page.
QtObject {
  id: root

  property var service: null
  // The query without paging: ["list"], ["list", "--collection", name] or
  // ["search", "--q", text]. An empty list shows nothing and asks for nothing.
  property var args: []
  // A chip id, "" for none.
  property string facet: ""
  // Cards per request; the page sizes it to fill its viewport and then some.
  property int pageSize: 24

  property var memories: []
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
  onArgsChanged: Qt.callLater(root.reload)
  onFacetChanged: Qt.callLater(root.reload)
  Component.onCompleted: Qt.callLater(root.reload)

  function query(extra) {
    var command = root.args.slice()
    if (root.facet.length)
      command = command.concat(["--facet", root.facet])
    return command.concat(extra)
  }

  // A fresh first page, for a new query or chip.
  function reload() {
    root.token++
    root.memories = []
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
    root.fetch(Math.max(root.pageSize, root.memories.length), "", false)
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
      var page = json.memories || json.results || []
      var info = json.pageInfo || {}
      root.memories = append ? root.memories.concat(page) : page
      root.total = info.total || 0
      root.hasNextPage = info.hasNextPage === true
      root.endCursor = info.endCursor || ""
      root.loaded = true
    })
  }
}
