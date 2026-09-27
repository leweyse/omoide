import QtQuick
import qs.Commons
import qs.Ui
import "../MemoryModel.js" as Model
import "../common"
import "../components"

// Upcoming / Past / Completed, with the agent's suggestions under Upcoming.
//
// Grouping is derived from the item's own due date and completion, never from
// a reminder's state: an alarm that already fired says nothing about whether
// the to-do is done, so overdue items stay in Past until ticked off.
Flickable {
  id: root

  // Whether this page holds the keyboard. The window gives it to the rail or
  // the page, never both, so the page draws its cursor only while it holds it.
  // Otherwise a highlighted row looks ready for Enter while the keys still go
  // to the sidebar.
  property bool hasKeyboard: true

  property var service: null
  signal openMemory(string id)
  signal openItem(string id)

  // Which tab is showing. Upcoming, because that is what you came to look at.
  property string tab: "upcoming"

  // The tab's tasks and, on Upcoming, the agent's suggestions, each a page at
  // a time. The tab counts come from the index, which counts every item.
  PagedList {
    id: tabPages
    service: root.service
    args: ["archive", "--group", root.tab]
    listKey: "items"
    pageSize: 40
  }
  PagedList {
    id: suggestionPages
    service: root.service
    args: root.tab === "upcoming" ? ["archive", "--group", "suggested"] : []
    listKey: "items"
    pageSize: 20
  }
  readonly property var tabRows: tabPages.rows
  readonly property var todoCounts: (root.service && root.service.index.todoCounts) || ({})

  // --- keyboard ------------------------------------------------------------
  //
  // Two regions: your tasks, then the agent's suggestions. Tab crosses between
  // them; the arrows stay inside one.

  readonly property var tabOrder: ["upcoming", "past", "completed"]
  readonly property var suggestions: suggestionPages.rows
  readonly property bool hasSuggestions:
    root.tab === "upcoming" && root.suggestions.length > 0

  readonly property int regionCount: root.hasSuggestions ? 2 : 1
  property int region: 0
  property int cursor: -1

  readonly property var regionRows:
    root.region === 1 ? root.suggestions : root.tabRows

  // Explicit index, not a read of `regionRows`: that is a binding on `region`,
  // and reading it inside region's own change handler can return the region
  // just left.
  function rowsFor(i) {
    return i === 1 ? root.suggestions : root.tabRows
  }

  // Tab lands on the target region's FIRST row, not the last position in it:
  // the same rule everywhere, so Tab is predictable.
  onRegionChanged: root.cursor = root.rowsFor(root.region).length > 0 ? 0 : -1

  // A tab switch replaces the rows under the cursor, so an index into the old
  // set means nothing. Region goes back to 0 because only Upcoming has two.
  onTabChanged: { root.region = 0; root.cursor = -1 }

  // Called by the dialog when you enter this page, so the first row lights up
  // straight away rather than waiting for an arrow key.
  // Coming back to the page: the row last touched keeps the cursor while it is
  // still there, and the page scrolls to it; otherwise the first row takes it.
  function focusResume() {
    if (root.cursor >= 0 && root.cursor < root.rowsFor(root.region).length) {
      root.ensureVisible()
      return
    }
    root.focusFirst()
  }

  // A click is a touch: the clicked row takes the cursor, so coming back to the
  // page lands on it.
  function touch(region, id) {
    root.region = region
    var rows = root.rowsFor(region)
    for (var i = 0; i < rows.length; i++)
      if (rows[i].id === id) { root.cursor = i; break }
  }

  function focusFirst() {
    // Upcoming can be empty while suggestions are not; land on whichever has
    // rows so entering the page always lights something up.
    var target = root.rowsFor(0).length > 0 ? 0
               : (root.rowsFor(1).length > 0 ? 1 : 0)
    root.region = target
    // rowsFor(target), not regionRows: entering when the region is unchanged
    // fires no change handler, and the binding can see the region you left.
    root.cursor = root.rowsFor(target).length > 0 ? 0 : -1
  }

  function pageKey(event) {
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
      var d = event.key === Qt.Key_Right ? 1 : -1
      var i = root.tabOrder.indexOf(root.tab)
      var next = i + d
      // Left at the first tab is NOT consumed: it falls through so the dialog
      // can take it and return to the sidebar. That is the "left edge exits"
      // rule, and it is why pageKey reports what it did not use.
      if (next < 0 || next >= root.tabOrder.length) return false
      root.tab = root.tabOrder[next]
      return true
    }

    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      var moved = Model.stepList(root.regionRows.length, root.cursor,
                                 event.key === Qt.Key_Down ? 1 : -1)
      if (moved === null) {
        // At the end of what is loaded: ask for the next page and stay put.
        if (event.key === Qt.Key_Down) (root.region === 1 ? suggestionPages : tabPages).loadMore()
        return true
      }
      root.cursor = moved
      root.ensureVisible()
      return true
    }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var row = root.regionRows[root.cursor]
      if (row) root.openItem(row.id)
      return true
    }

    // Space ticks the box without opening anything. The point of a task list is
    // clearing it, and that should not cost a dialog each time.
    if (event.key === Qt.Key_Space) {
      root.toggleCursor()
      return true
    }

    return false
  }

  // Scroll the cursor back into view, in content coordinates: a row sits inside
  // a card inside the page, so its own y says nothing about where it is.
  function toggleCursor() {
    var args = Model.todoAction(root.regionRows[root.cursor])
    if (!args || !root.service) return
    root.service.call(args, function () { root.service.refresh() })
  }

  function ensureVisible() {
    var group = root.region === 1 ? suggestedGroup : tasksGroup
    var it = group.itemAt(root.cursor)
    if (!it) return
    var top = it.mapToItem(layout, 0, 0).y
    var bottom = top + it.height
    // The page's own edge inset, the same one contentHeight adds below the
    // last row: scrolling something into view should leave the gap the page
    // already keeps at its edges, not a second, smaller one of its own.
    var pad = Style.spacing.panelPadding
    var limit = Math.max(0, root.contentHeight - root.height)
    if (top - pad < root.contentY)
      root.contentY = Math.max(0, top - pad)
    else if (bottom + pad > root.contentY + root.height)
      root.contentY = Math.min(limit, bottom + pad - root.height)
  }

  // Bottom inset only. The gap above belongs to the window's view
  // loader, so it is chrome and survives scrolling.
  contentHeight: layout.implicitHeight + Style.spacing.panelPadding
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  PageWheel { page: root }

  // True once the tab's first page has answered. Until then the list is drawn
  // as placeholder rows; a re-fetch after an edit keeps the rows it has.
  readonly property bool loaded: tabPages.loaded

  // Rows replaced under the cursor: ticking a task removes it from Upcoming,
  // and the suggestions card can disappear while focus is in it.
  function settleCursor() {
    if (root.cursor >= root.regionRows.length)
      root.cursor = root.regionRows.length - 1
    if (root.region >= root.regionCount) {
      root.region = 0
      root.cursor = root.rowsFor(0).length > 0 ? 0 : -1
    }
    // The rows arrive AFTER the page is entered, so the first-item focus that
    // ran on entry found an empty list. Seed it now that there is one.
    if (root.cursor < 0 && root.regionRows.length > 0) root.cursor = 0
  }
  Connections {
    target: tabPages
    function onRowsChanged() { root.settleCursor() }
  }
  Connections {
    target: suggestionPages
    function onRowsChanged() { root.settleCursor() }
  }

  // The item editor is a separate surface, so a delete or a completion made
  // there has to reach this list somehow. Every mutation makes the service pull
  // a new index, so its index changing is the general "data moved" signal.
  Connections {
    target: root.service
    function onIndexChanged() {
      tabPages.refreshLoaded()
      suggestionPages.refreshLoaded()
    }
  }

  // The next page while a viewport of rows is still below: the tab's tasks
  // first, then the suggestions under them.
  function maybeLoadMore() {
    if (root.contentY + root.height * 2 < root.contentHeight) return
    if (tabPages.hasNextPage) tabPages.loadMore()
    else suggestionPages.loadMore()
  }
  onContentYChanged: root.maybeLoadMore()
  onContentHeightChanged: root.maybeLoadMore()

  Column {
    id: layout
    x: Style.spacing.panelPadding
    y: 0
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxxl

    // Buttons, not chips: a chip is a filter added to a set, a tab is a switch
    // between whole views.
    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      Repeater {
        model: [
          { key: "upcoming",  label: "Upcoming" },
          { key: "past",      label: "Past" },
          { key: "completed", label: "Completed" }
        ]

        delegate: TabButton {
          required property var modelData
          // The tab's own tasks only. Suggestions are a section of their own
          // with its own heading, so counting them here would promise more
          // tasks than the first card holds.
          label: modelData.label
          count: root.todoCounts[modelData.key] || 0
          selected: root.tab === modelData.key
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.resolvedFamily
          onClicked: root.tab = modelData.key
        }
      }
    }

    // Where the tasks will be, drawn to TaskGroup's card and TodoRow's height.
    BorderSurface {
      visible: !root.loaded
      width: parent.width
      height: skeletonRows.implicitHeight + Style.spacing.lg * 2
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)

      Column {
        id: skeletonRows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.lg
        spacing: Style.spacing.sm

        Repeater {
          model: [0.7, 0.5, 0.6, 0.4]

          delegate: Item {
            required property real modelData
            width: skeletonRows.width
            height: Style.space(34)

            Skeleton {
              anchors.verticalCenter: parent.verticalCenter
              x: Style.spacing.md
              width: (parent.width - Style.spacing.md * 2) * parent.modelData
              height: Style.font.body
            }
          }
        }
      }
    }

    // Your tasks. Unlabelled: the tab above already says which set this is.
    TaskGroup {
      id: tasksGroup
      width: parent.width
      rows: root.tabRows
      cursor: root.hasKeyboard && root.region === 0 ? root.cursor : -1
      service: root.service
      onChanged: if (root.service) root.service.refresh()
      onOpenItem: function (id) { root.touch(0, id); root.openItem(id) }
    }

    // The agent's proposals, in a card of their own. Kept apart from the list
    // above rather than appended to it: accepting one is a decision, and a
    // proposal sitting in the same card as your real tasks reads as though it
    // had already been accepted.
    //
    // Upcoming only. A suggestion has no date yet, so it cannot be overdue and
    // cannot have been completed.
    TaskGroup {
      id: suggestedGroup
      width: parent.width
      visible: root.hasSuggestions
      label: "SUGGESTED"
      rows: root.suggestions
      cursor: root.hasKeyboard && root.region === 1 ? root.cursor : -1
      service: root.service
      onChanged: if (root.service) root.service.refresh()
      onOpenItem: function (id) { root.touch(1, id); root.openItem(id) }
    }

    Text {
      visible: root.loaded && root.tabRows.length === 0
               && !(root.tab === "upcoming"
                    && (root.todoCounts.suggested || 0) > 0)
      width: parent.width
      text: root.tab === "upcoming" ? "Nothing coming up."
            : (root.tab === "past" ? "Nothing overdue."
                                   : "Nothing completed yet.")
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.subtitle
    }

  }
}
