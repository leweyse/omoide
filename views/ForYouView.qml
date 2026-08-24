import QtQuick
import qs.Commons
import qs.Ui
import "../MemoryModel.js" as Model
import "../components"

// A digest of what is live, not a list of everything.
Flickable {
  id: root

  property var service: null
  signal openMemory(string id)
  signal openItem(string id)
  signal openArchive()

  readonly property var index: service ? service.index : ({})

  // --- keyboard ------------------------------------------------------------
  //
  // Two regions: the events carousel, then the task rows. Tab crosses between
  // them, and so does Down at the bottom of Events -- the carousel is one row
  // deep, so Down there has nothing else to mean.

  readonly property var events: root.index.events || []
  readonly property var tasks: (root.index.todos || []).slice(0, 8)

  readonly property int regionCount: 2
  property int region: 0
  property int cursor: -1

  readonly property var regionRows: root.region === 1 ? root.tasks : root.events

  // Takes the index explicitly rather than reading `regionRows`, which is a
  // binding on `region`: the order between a binding updating and that
  // property's own change handler is undefined, so reading it in here can see
  // the region you just left.
  function rowsFor(i) { return i === 1 ? root.tasks : root.events }

  function enterRegion(i) {
    root.cursor = root.rowsFor(i).length > 0 ? 0 : -1
  }

  onRegionChanged: root.enterRegion(root.region)

  // Called by the dialog when you enter this page, so the first row lights up
  // straight away rather than waiting for an arrow key.
  function focusFirst() {
    root.region = 0
    // Explicitly: entering when region is already 0 fires no change handler.
    root.enterRegion(0)
  }

  function pageKey(event) {
    // Events is horizontal, so it takes the horizontal keys; Tasks is vertical
    // and takes none, which is what lets Left there fall through to the sidebar.
    if (root.region === 0
        && (event.key === Qt.Key_Right || event.key === Qt.Key_Left)) {
      var moved = Model.stepList(root.events.length, root.cursor,
                                 event.key === Qt.Key_Right ? 1 : -1)
      // Left at the first event is not consumed: the dialog takes it and
      // returns to the sidebar. Right at the last one is simply swallowed.
      if (moved === null) return event.key === Qt.Key_Right
      root.cursor = moved
      return true
    }

    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      var d = event.key === Qt.Key_Down ? 1 : -1

      // Events is ONE row deep. It owns the horizontal keys, so a vertical key
      // there can only mean "leave" -- stepping the events list on Down walked
      // to the next card instead of crossing into Tasks.
      if (root.region === 0) {
        if (d > 0 && root.tasks.length > 0) root.region = 1
        return true
      }

      var next = Model.stepList(root.tasks.length, root.cursor, d)
      if (next !== null) { root.cursor = next; return true }
      // Up off the first task goes back to the carousel. One continuous column,
      // which is how the page reads even though the halves differ in shape.
      if (d < 0 && root.events.length > 0) root.region = 0
      return true
    }

    // Tasks only. An event has no completion state, so Space there means
    // nothing and must not silently do something else.
    if (event.key === Qt.Key_Space && root.region === 1) {
      var args = Model.todoAction(root.tasks[root.cursor])
      if (args && root.service)
        root.service.call(args, function () { root.service.refresh() })
      return true
    }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var row = root.regionRows[root.cursor]
      if (!row) return true
      // An event goes straight to its capture; a task opens its editor. Same
      // split as the mouse, so the keyboard is not a second set of rules.
      if (root.region === 0) root.openMemory(row.memoryId)
      else root.openItem(row.id)
      return true
    }

    return false
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

  Column {
    id: layout
    x: Style.spacing.panelPadding
    y: 0
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxl

    Column {
      width: parent.width
      spacing: Style.spacing.sm
      visible: (root.index.events || []).length > 0

      Row {
        width: parent.width
        PanelSectionHeader {
          text: "EVENTS"
          foreground: Color.muted
          fontFamily: Style.font.resolvedFamily
        }
      }

      ListView {
        width: parent.width
        // A ListView sizes its delegates across the scroll axis, so THIS is the
        // card height -- EventCard's own content-driven height never applies in
        // here. 158 was sized for the old fixed-height card and left a band of
        // nothing between the carousel and Tasks.
        //
        // 96 is the worst case a card needs: a two-line title, the time range,
        // the place, and the card's padding. Cards in a carousel want to be
        // uniform anyway, and each one centres its own content vertically.
        height: Style.space(96)
        orientation: ListView.Horizontal
        spacing: Style.spacing.md
        clip: true
        model: root.events

        delegate: EventCard {
          required property var modelData
          required property int index
          event: modelData
          hasCursor: root.region === 0 && root.cursor === index
          // Straight to the capture, not to the item editor. An event's own
          // fields are on its memory page anyway, and the reason you tap one
          // here is to see what you saved -- the ticket, the poster, the page.
          // Tasks below still open their editor, because a to-do is a thing you
          // act on rather than something you read.
          onActivated: root.openMemory(modelData.memoryId)
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.sm

      Item {
        width: parent.width
        height: tasksHeader.implicitHeight

        PanelSectionHeader {
          id: tasksHeader
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "TASKS"
          foreground: Color.muted
          fontFamily: Style.font.resolvedFamily
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.subtitle
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openArchive()
          }
        }
      }

      Repeater {
        model: root.tasks

        delegate: TodoRow {
          required property var modelData
          required property int index
          width: parent.width
          item: modelData
          hasCursor: root.region === 1 && root.cursor === index
          service: root.service
          onChanged: if (root.service) root.service.refresh()
          onActivated: root.openItem(modelData.id)
        }
      }

      Text {
        visible: (root.index.todos || []).length === 0
        text: "No open to-dos."
        color: Color.muted
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
