import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model
import "../common/Radii.js" as Radii

// One card in the For you carousel: the calendar tile, the event, and its art.
//
// It used to be a fixed 150px tall with everything crammed against the top, so
// an event with a title and one line left about a hundred pixels of nothing
// underneath. It now sizes to its content with a floor, and takes the same
// calendar tile the Event Date block uses.
BorderSurface {
  id: root

  property var event: ({})
  // Keyboard cursor, set by the carousel from the page's cursor.
  property bool hasCursor: false
  signal activated()

  readonly property var badge: Model.dateBadge(event ? event.startsAt : "")
  readonly property real pad: Style.spacing.xxxl
  readonly property string place: {
    if (!root.event) return ""
    var parts = []
    if (root.event.location) parts.push(root.event.location)
    if (root.event.domain) parts.push(root.event.domain)
    return parts.join("  ·  ")
  }

  // A fallback, not the width it draws at in the carousel: the row fits a
  // whole number of cards to its own width and hands each one the result. The
  // artwork is a fixed strip and the body fills what is left, so the extra
  // width goes to the title.
  width: Style.space(300)
  height: Math.max(Style.space(96), body.implicitHeight + root.pad * 2)
  radius: Style.cornerRadius
  color: Color.popups.background
  // The outline-button border, not popups.border -- that token defaults to the
  // ACCENT, so an accent focus ring on a card was invisible against every
  // unfocused card beside it. Same width, so nothing reflows.
  // Accent on focus. The width does NOT change -- a card measures its height
  // as content plus border widths, so a thicker focus border would resize the
  // card and reflow the grid on every arrow key.
  borderSpec: root.hasCursor
              ? Border.flat(Color.accent, 1)
              : Border.controlSpec("normal", Color.popups.text, Color.accent)

  FocusRing {
    anchors.fill: parent
    radius: root.radius
    hasCursor: root.hasCursor
    // Artwork bleeds under the ring on this card, so it gets the dark
    // companion line: whichever of the two loses contrast against the
    // thumbnail, the other keeps it.
    twoTone: true
    hot: hoverArea.containsMouse
  }

  MouseArea {
    id: hoverArea
    hoverEnabled: true
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
      topRightRadius: Radii.nested(Style.cornerRadius, root.borderRight)
      bottomRightRadius: Radii.nested(Style.cornerRadius, root.borderBottom)
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
    spacing: Style.spacing.lg

    DateBadge {
      id: badge
      month: root.badge.top
      day: root.badge.bottom
    }

    Column {
      width: parent.width - badge.width - Style.spacing.lg
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: Model.truncate(root.event ? root.event.title : "", 70)
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: Color.popups.text
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.title
      }

      Text {
        width: parent.width
        visible: text.length > 0
        text: root.event
              ? Model.formatRange(root.event.startsAt, root.event.endsAt,
                                  root.event.allDay)
              : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Color.popups.text
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        visible: root.place.length > 0
        // location and domain are model output, so never sniffed for markup.
        text: root.place
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Color.muted
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
