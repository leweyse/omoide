import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model

// "Event Date" is a canonical label; the date badge and the range come from
// the item row, not from the block payload.
BlockCard {
  id: root
  property var payload: ({})
  property var item: null
  property var service: null
  signal changed()
  // Reminders are edited in the item editor, and until now nothing on this
  // block could open it -- an event's alarms were visible and unreachable.
  signal openItem(var item)
  heading: "Event Date"

  // One control, in the corner, rather than a chip in the flow and click
  // handlers on the text. Everything it opens -- the time, the place, the
  // alarms -- lives in the item editor, so one affordance says so once.
  trailing: Component {
    PanelActionButton {
      bordered: true
      iconText: "󰏫"
      tooltipText: "Edit this event and its reminders"
      size: Style.space(24)
      foreground: Color.popups.text
      hoverColor: Color.accent
      fontFamily: Style.font.resolvedFamily
      onClicked: if (root.item) root.openItem(root.item)
    }
  }

  readonly property int pendingReminders: {
    var list = (root.item && root.item.reminders) || []
    var n = 0
    for (var i = 0; i < list.length; i++)
      if (list[i].status === "pending") n++
    return n
  }

  readonly property var badge: Model.dateBadge(item ? item.startsAt : "")

  Column {
    width: parent.width
    // The card's own sections: the details, the rule, the reminders. A wider
    // gap than the lines WITHIN the details, so the grouping is legible --
    // 4px inside a group, 12px between groups.
    spacing: Style.spacing.xxl

    Row {
      width: parent.width
      spacing: Style.spacing.md

      DateBadge {
        id: badge
        month: root.badge.top
        day: root.badge.bottom
      }

      Column {
        width: parent.width - badge.width - Style.spacing.md
        // The time, the place and the map link sat 3px apart, which read as one
        // wrapped paragraph rather than three separate facts.
        spacing: Style.spacing.sm

        Text {
          width: parent.width
          text: root.item
                ? Model.formatRange(root.item.startsAt, root.item.endsAt, root.item.allDay)
                : ""
          wrapMode: Text.WordWrap
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
        }

        Text {
          visible: !!(root.item && root.item.location)
          width: parent.width
          text: root.item ? (root.item.location || "") : ""
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          spacing: Style.spacing.md

          Text {
            visible: !!(root.item && root.item.location)
            text: "Google Maps"
            color: Color.accent
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var url = root.item && root.item.mapUrl
                          ? root.item.mapUrl
                          : "https://www.google.com/maps/search/?api=1&query="
                            + encodeURIComponent(root.item ? root.item.location : "")
                Quickshell.execDetached(["omarchy", "launch", "browser", url])
              }
            }
          }
        }

      }
    }

    // What the event IS, above; what you will be told about it, below. Two
    // concerns in one card, so a rule between them rather than one more line in
    // the same list. Full width, not inside the text column: it separates
    // sections of the card, and starting it level with the text would read as
    // part of the details.
    PanelSeparator {
      visible: root.pendingReminders > 0
      width: parent.width
      foreground: Color.popups.text
    }

    // Pending only: a fired or cancelled row is history, not a promise. Editing
    // them is the corner button's job.
    Column {
      visible: root.pendingReminders > 0
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.item ? (root.item.reminders || []) : []

        delegate: Text {
          required property var modelData
          visible: modelData.status === "pending" && text.length > 0
          width: parent.width
          text: Model.reminderLine(modelData)
          color: Color.accent
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
