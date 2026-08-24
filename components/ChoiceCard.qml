import QtQuick
import qs.Commons
import qs.Ui

// One selectable card: a radio, a name, and a line describing what picking it
// does. Shared by the agent grid and the screenshot-input grid in
// SettingsDialog, so the two read as one kind of choice rather than a list and
// a toggle -- and so the radio offset, the gap and the type sizes cannot drift
// apart between them.
//
// An unavailable choice is shown dimmed with the reason in `detail` rather
// than hidden, the same way an uninstalled agent is.
CursorSurface {
  id: root

  property string title: ""
  property string detail: ""
  property bool picked: false
  property bool selectable: true

  signal chose()

  height: body.implicitHeight + Style.spacing.lg * 2
  radius: Style.space(5)
  hasCursor: root.picked
  bordered: false
  foreground: Color.menu.text
  opacity: root.selectable ? 1.0 : 0.45

  MouseArea {
    anchors.fill: parent
    cursorShape: root.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.selectable) root.chose()
  }

  Row {
    anchors.fill: parent
    anchors.margins: Style.spacing.lg
    spacing: Style.spacing.lg

    Text {
      // Level with the title, not centred on the card: centring a radio
      // against two lines leaves it floating in the gap between them. Same
      // pixelSize as the title so the two line boxes align without a magic
      // offset.
      anchors.top: body.top
      width: Style.space(12)
      horizontalAlignment: Text.AlignHCenter
      text: root.picked ? "●" : "○"
      color: root.picked ? Color.accent : Color.muted
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.subtitle
    }

    Column {
      id: body
      anchors.top: parent.top
      width: parent.width - Style.space(12) - Style.spacing.lg
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.title
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.detail
        wrapMode: Text.WordWrap
        color: Color.muted
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
