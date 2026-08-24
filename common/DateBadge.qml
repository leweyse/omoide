import QtQuick
import qs.Commons

// The calendar tile: month above, day below.
//
// One component because there were two copies -- the Event Date block and the
// For you card -- at different sizes, with different fills, and one of them
// nested inside the card's artwork, so a card with no thumbnail showed no date
// at all.
//
// Children are sized and aligned rather than anchored: anchors on the children
// of a positioner are not supported.
Rectangle {
  id: root

  property string month: ""
  property string day: ""
  property real size: Style.space(38)

  width: size
  height: size
  radius: Style.space(4)
  color: Style.normalFillFor(Color.popups.text, Color.accent, Color.urgent)

  Column {
    anchors.centerIn: parent
    width: parent.width

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.month
      color: Color.urgent
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.day
      color: Color.popups.text
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.subtitle
    }
  }
}
