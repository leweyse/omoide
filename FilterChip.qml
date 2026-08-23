import QtQuick
import qs.Commons
import qs.Ui

// One filter chip: label, count, selected state.
BorderSurface {
  id: root

  property string label: ""
  property string icon: ""
  property int count: 0
  property bool selected: false
  signal picked()

  readonly property bool hot: mouse.containsMouse

  implicitWidth: content.implicitWidth + Style.spacing.md * 2
  implicitHeight: Style.space(24)
  width: implicitWidth
  height: implicitHeight
  radius: height / 2
  color: root.selected
         ? Style.selectedFillFor(Color.popups.text, Color.accent, Color.urgent)
         : (root.hot ? Style.hoverFillFor(Color.popups.text, Color.accent, Color.urgent)
                     : "transparent")
  borderSpec: Border.controlSpec(root.selected ? "selected"
                                 : (root.hot ? "hover-cursor" : "normal"),
                                 Color.popups.text, Color.accent, Color.urgent)

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.picked()
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.icon.length > 0
      text: root.icon
      color: root.selected ? Color.accent : Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.selected ? Color.accent : Color.popups.text
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

    // Level with the label, not raised. It was offset up as a superscript,
    // copying the reference UI, which at 8px against a 10px label just read as
    // misaligned rather than as typography.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.count > 0
      text: root.count
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.max(8, Style.font.caption - 2)
    }
  }
}
