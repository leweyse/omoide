import QtQuick
import qs.Commons
import qs.Ui
import "../MemoryModel.js" as Model
import "../components"

// A digest of what is live, not a list of everything.
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
  signal openArchive()

  readonly property var index: service ? service.index : ({})

  // --- keyboard ------------------------------------------------------------
  //
  // Two regions: the events carousel, then the task rows. Tab crosses between
  // them, and so does Down in Events. The carousel is one row deep, so Down
  // there has nothing else to mean.

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
    // The first region with anything in it: a day can have tasks and no
    // events, and entering the empty carousel highlights nothing at all.
    var target = root.events.length > 0 ? 0 : (root.tasks.length > 0 ? 1 : 0)
    root.region = target
    // Explicitly: entering when the region is unchanged fires no handler.
    root.enterRegion(target)
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

      // Events is one row deep and owns the horizontal keys, so a vertical key
      // there only means "leave".
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
      // The carousel owns the wheel while the pointer is over it, but only
      // while it has somewhere to go -- otherwise a pointer resting on it
      // would deaden the page's own scroll.
      if (eventsHover.hovered && eventsRow.overflowing) return
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
    spacing: Style.spacing.xxxl

    Column {
      width: parent.width
      spacing: Style.spacing.lg
      visible: (root.index.events || []).length > 0

      Row {
        width: parent.width
        PanelSectionHeader {
          text: "EVENTS"
          foreground: Color.muted
          fontFamily: Style.font.resolvedFamily
        }
      }

      // The clip that lets the row scroll, held a pixel OUTSIDE the cards: a
      // focused card draws its accent border on the device pixel that rounds
      // just outside its own bounds, and a clip on that line cuts the first
      // card's border. Above and below too: where the cards' top and bottom
      // pixel rows land against a clip that fits them exactly varies from frame
      // to frame, so a scrolled row loses its top edge. The wrapper holds the
      // row's own height, so the layout does not grow. The row itself keeps its
      // position.
      Item {
        id: eventsClip
        readonly property real bleed: Math.max(1, Style.space(1))
        x: -bleed
        width: parent.width + bleed * 2
        height: Style.space(96)
        clip: true

        // Cards are sized from the row rather than pinned, so a whole number of
        // them fits whatever width the dialog opens at and the rest scroll. A
        // fixed card width ended the carousel mid-card at most widths, which
        // reads as a clipping fault rather than as an overflow.
        ListView {
          id: eventsRow
          x: eventsClip.bleed
          width: eventsClip.width - eventsClip.bleed * 2
          // A ListView sizes its delegates across the scroll axis, so THIS is the
          // card height -- EventCard's own content-driven height never applies in
          // here. 158 was sized for the old fixed-height card and left a band of
          // nothing between the carousel and Tasks.
          //
          // 96 is the worst case a card needs: a two-line title, the time range,
          // the place, and the card's padding. Cards in a carousel want to be
          // uniform anyway, and each one centres its own content vertically.
          height: parent.height
          orientation: ListView.Horizontal
          spacing: Style.spacing.lg
          model: root.events

          // The narrowest a card may be: below it the title has no room beside
          // the date badge and the artwork. Above it cards stretch to close the
          // remainder, which the extra width spends on the title.
          readonly property real cardMin: Style.space(300)
          readonly property int cardColumns:
            Math.max(1, Math.floor((width + spacing) / (cardMin + spacing)))
          // Floored, not rounded: rounding up overshoots the row by a pixel per
          // card and slices the last one again.
          readonly property real cardWidth:
            Math.floor((width - spacing * (cardColumns - 1)) / cardColumns)

          // The scroll, in the view's own coordinates. originX is NOT 0 here --
          // followCursor explains why -- so every bound is measured from it.
          readonly property real stride: cardWidth + spacing
          readonly property real span: count > 0 ? count * stride - spacing : 0
          // Functions, not bindings: followCursor runs from onOriginXChanged, and
          // whether a binding ON originX has re-evaluated by the time that
          // property's own change handler runs is undefined. Read as bindings
          // there, both bounds came from the PREVIOUS origin and clamped the row
          // straight back onto the wrong card.
          function minX() { return originX }
          function maxX() { return originX + Math.max(0, span - width) }
          readonly property bool overflowing: span > width + 0.5

          // Keep the keyboard cursor on screen, and the row anchored to its own
          // start otherwise. Measured from originX for the reason the library's
          // collections row documents at length: delegates are created before the
          // row has a width, and the ListView answers their resize by shifting
          // the content origin, which leaves contentX pointing at the wrong card.
          //
          // The cursor means a task while the region is Tasks, so the card it
          // follows is only this row's while the region is Events -- otherwise
          // arrowing down the task list would drag the carousel along with it.
          function followCursor() {
            if (count === 0 || width <= 0 || cardWidth <= 0) return
            var x = Math.max(minX(), Math.min(maxX(), contentX))
            if (root.region !== 0) { contentX = x; return }
            var left = originX + Math.max(0, root.cursor) * stride
            if (left < x) x = left
            else if (left + cardWidth > x + width) x = left + cardWidth - width
            contentX = Math.max(minX(), Math.min(maxX(), x))
          }

          onWidthChanged: eventsRow.followCursor()
          onCountChanged: eventsRow.followCursor()
          onOriginXChanged: eventsRow.followCursor()

          Connections {
            target: root
            function onCursorChanged() { eventsRow.followCursor() }
            function onRegionChanged() { eventsRow.followCursor() }
          }

          delegate: EventCard {
            required property var modelData
            required property int index
            width: eventsRow.cardWidth
            event: modelData
            hasCursor: root.hasKeyboard && root.region === 0 && root.cursor === index
            // Straight to the capture, not to the item editor. An event's own
            // fields are on its memory page anyway, and the reason you tap one
            // here is to see what you saved -- the ticket, the poster, the page.
            // Tasks below still open their editor, because a to-do is a thing you
            // act on rather than something you read.
            onActivated: root.openMemory(modelData.memoryId)
          }

          // A vertical wheel over the carousel scrolls it sideways. With the
          // cards fitted to the width there is no half-card hinting at an
          // overflow, so reaching it must not depend on owning a horizontal wheel.
          WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (event) {
              // Nothing to scroll: leave the event alone so the page still moves
              // under a pointer that happens to be resting here.
              if (!eventsRow.overflowing) return
              var delta = event.angleDelta.y !== 0 ? event.angleDelta.y
                                                   : event.angleDelta.x
              if (delta === 0) return
              // One whole card per notch, so the row lands on card boundaries
              // rather than part-way across one. Clamped to the row's own bounds,
              // which start at originX rather than at 0.
              eventsRow.contentX =
                Math.max(eventsRow.minX(),
                         Math.min(eventsRow.maxX(),
                                  eventsRow.contentX
                                  - delta / 120 * eventsRow.stride))
              event.accepted = true
            }
          }

          // Which handler gets a wheel is decided by hover, not by hoping the
          // accepted flag propagates between two independent handlers.
          HoverHandler { id: eventsHover }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.lg

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
          font.pixelSize: Style.font.title
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
          hasCursor: root.hasKeyboard && root.region === 1 && root.cursor === index
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
        font.pixelSize: Style.font.subtitle
      }
    }
  }
}
