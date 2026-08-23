import QtQuick
import qs.Commons
import qs.Ui
import ".." as Root
import "../blocks" as Blocks
import "../MemoryModel.js" as Model

// A digest of what is live, not a list of everything.
Flickable {
  id: root

  property var service: null
  signal openMemory(string id)
  signal openItem(string id)
  signal openArchive()

  readonly property var index: service ? service.index : ({})

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
        model: root.index.events || []

        delegate: Root.EventCard {
          required property var modelData
          event: modelData
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
        model: (root.index.todos || []).slice(0, 8)

        delegate: Blocks.TodoRow {
          required property var modelData
          width: parent.width
          item: modelData
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
