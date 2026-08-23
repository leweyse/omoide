import QtQuick
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model

// One card in the For you carousel: the calendar tile, the event, and its art.
//
// It used to be a fixed 150px tall with everything crammed against the top, so
// an event with a title and one line left about a hundred pixels of nothing
// underneath. It now sizes to its content with a floor, and takes the same
// calendar tile the Event Date block uses.
BorderSurface {
  id: root

  property var event: ({})
  signal activated()

  readonly property var badge: Model.dateBadge(event ? event.startsAt : "")
  readonly property real pad: Style.spacing.xxl
  readonly property string place: {
    if (!root.event) return ""
    var parts = []
    if (root.event.location) parts.push(root.event.location)
    if (root.event.domain) parts.push(root.event.domain)
    return parts.join("  ·  ")
  }

  width: Style.space(300)
  height: Math.max(Style.space(96), body.implicitHeight + root.pad * 2)
  radius: Style.cornerRadius
  color: Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  // Bleeds to the card's right edge, inside the border rather than over it.
  Item {
    id: art
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: root.borderRight
    anchors.topMargin: root.borderTop
    anchors.bottomMargin: root.borderBottom
    width: visible ? Style.space(96) : 0
    visible: !!(root.event && root.event.thumb)
    clip: true

    RoundedImage {
      anchors.fill: parent
      source: root.event && root.event.thumb ? "file://" + root.event.thumb : ""
      fillMode: Image.PreserveAspectCrop
      borderWidth: 0
      // Only the corners it actually touches.
      topLeftRadius: 0
      bottomLeftRadius: 0
      topRightRadius: Math.max(0, Style.cornerRadius - root.borderRight)
      bottomRightRadius: Math.max(0, Style.cornerRadius - root.borderBottom)
    }
  }

  Row {
    id: body
    anchors.left: parent.left
    anchors.right: art.left
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    // Centred against the card, so a one-line event does not sit at the top of
    // a taller box next to its artwork.
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.md

    DateBadge {
      id: badge
      month: root.badge.top
      day: root.badge.bottom
    }

    Column {
      width: parent.width - badge.width - Style.spacing.md
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        text: Model.truncate(root.event ? root.event.title : "", 70)
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: Color.popups.text
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.subtitle
      }

      Text {
        width: parent.width
        visible: text.length > 0
        text: root.event
              ? Model.formatRange(root.event.startsAt, root.event.endsAt,
                                  root.event.allDay)
              : ""
        elide: Text.ElideRight
        color: Color.popups.text
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: root.place.length > 0
        text: root.place
        elide: Text.ElideRight
        color: Color.muted
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
