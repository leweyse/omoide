import QtQuick
import qs.Commons
import qs.Ui
import "../MemoryModel.js" as Model
import "../common"

// Upcoming / Past / Anytime / Completed.
//
// Grouping is derived from the item's own due date and completion, never from
// a reminder's state: an alarm that already fired says nothing about whether
// the to-do is done, so overdue items stay in Past until ticked off.
Flickable {
  id: root

  property var service: null
  signal openMemory(string id)
  signal openItem(string id)

  property var groups: ({ suggested: [], upcoming: [], past: [], completed: [] })
  // Which tab is showing. Upcoming, because that is what you came to look at.
  property string tab: "upcoming"

  // --- keyboard ------------------------------------------------------------
  //
  // Two regions: your tasks, then the agent's suggestions. Tab crosses between
  // them; the arrows stay inside one.

  readonly property var tabOrder: ["upcoming", "past", "completed"]
  readonly property var suggestions: root.groups.suggested || []
  readonly property bool hasSuggestions:
    root.tab === "upcoming" && root.suggestions.length > 0

  readonly property int regionCount: root.hasSuggestions ? 2 : 1
  property int region: 0
  property int cursor: -1

  readonly property var regionRows:
    root.region === 1 ? root.suggestions : (root.groups[root.tab] || [])

  // Explicit index, not a read of `regionRows`: that is a binding on `region`,
  // and reading it inside region's own change handler can return the region you
  // just left. With an empty tasks list and non-empty suggestions, Tab landed
  // nothing at all.
  function rowsFor(i) {
    return i === 1 ? root.suggestions : (root.groups[root.tab] || [])
  }

  // Tab lands on the target region's FIRST row, not wherever you last were in
  // it -- the same rule everywhere, so Tab is predictable.
  onRegionChanged: root.cursor = root.rowsFor(root.region).length > 0 ? 0 : -1

  // A tab switch replaces the rows under the cursor, so an index into the old
  // set means nothing. Region goes back to 0 because only Upcoming has two.
  onTabChanged: { root.region = 0; root.cursor = -1 }

  // Called by the dialog when you enter this page, so the first row lights up
  // straight away rather than waiting for an arrow key.
  function focusFirst() {
    root.region = 0
    // rowsFor(0), not regionRows: entering when region is already 0 fires no
    // change handler, and reading the binding here can see the region you left.
    root.cursor = root.rowsFor(0).length > 0 ? 0 : -1
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
      if (moved === null) return true   // at an end: swallow, do not exit
      root.cursor = moved
      root.ensureVisible()
      return true
    }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var row = root.regionRows[root.cursor]
      if (row) root.openItem(row.id)
      return true
    }

    // Space ticks the box without opening anything -- the point of a task list
    // is clearing it, and that should not cost a dialog each time.
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
    root.service.call(args, function () {
      root.reload()
      root.service.refresh()
    })
  }

  function ensureVisible() {
    var group = root.region === 1 ? suggestedGroup : tasksGroup
    var it = group.itemAt(root.cursor)
    if (!it) return
    var top = it.mapToItem(layout, 0, 0).y
    var bottom = top + it.height
    var pad = Style.spacing.xxxl
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

  // Flickable's built-in wheel step is tuned for touch flicking and crawls with
  // a mouse or touchpad, which is painful on a page this tall. One notch moves
  // a readable chunk instead, clamped so it cannot overscroll.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function (event) {
      if (event.angleDelta.y === 0) return
      var notches = event.angleDelta.y / 120
      var limit = Math.max(0, root.contentHeight - root.height)
      root.contentY = Math.max(0, Math.min(limit,
                                           root.contentY - notches * Style.space(140)))
    }
  }

  function reload() {
    if (!service) return
    service.call(["archive"], function (code, json) {
      if (json) root.groups = json
      // Ticking a task removes it from Upcoming, so the index the cursor held
      // can now be past the end.
      if (root.cursor >= root.regionRows.length)
        root.cursor = root.regionRows.length - 1
      // The suggestions card can disappear entirely while focus is in it.
      if (root.region >= root.regionCount) {
        root.region = 0
        root.cursor = root.rowsFor(0).length > 0 ? 0 : -1
      }
      // The rows arrive AFTER the page is entered, so the first-item focus that
      // ran on entry found an empty list. Seed it now that there is one.
      if (root.cursor < 0 && root.regionRows.length > 0) root.cursor = 0
    })
  }

  Component.onCompleted: reload()

  // The item editor is a separate surface, so a delete or a completion made
  // there has to reach this list somehow. Every mutation rewrites index.json
  // and pings the service, so its index changing is the general "data moved"
  // signal -- no direct wiring between the two surfaces needed.
  Connections {
    target: root.service
    function onIndexChanged() { root.reload() }
  }


  Column {
    id: layout
    x: Style.spacing.panelPadding
    y: 0
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxxl

    // Buttons, not chips: a chip is a filter you add to a set, a tab is a
    // switch between whole views, and at chip size it read as neither.
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
          count: (root.groups[modelData.key] || []).length
          selected: root.tab === modelData.key
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.resolvedFamily
          onClicked: root.tab = modelData.key
        }
      }
    }

    // Your tasks. Unlabelled: the tab above already says which set this is.
    TaskGroup {
      id: tasksGroup
      width: parent.width
      rows: root.groups[root.tab] || []
      cursor: root.region === 0 ? root.cursor : -1
      service: root.service
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (id) { root.openItem(id) }
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
      cursor: root.region === 1 ? root.cursor : -1
      service: root.service
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (id) { root.openItem(id) }
    }

    Text {
      visible: (root.groups[root.tab] || []).length === 0
               && !(root.tab === "upcoming"
                    && (root.groups.suggested || []).length > 0)
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
