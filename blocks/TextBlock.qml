import QtQuick
import qs.Commons
import qs.Ui

BlockCard {
  id: root

  // Correcting the agent. The pencil is in the card's corner rather than on the
  // text, so a block reads as prose until you go looking for the edit.
  signal editRequested()

  trailing: Component {
    PanelActionButton {
      bordered: true
      iconText: "󰏫"
      tooltipText: "Edit this"
      size: Style.space(24)
      foreground: Color.popups.text
      hoverColor: Color.accent
      fontFamily: Style.font.resolvedFamily
      onClicked: root.editRequested()
    }
  }
  property var payload: ({})
  property var service: null

  Column {
    width: parent.width
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.payload.text || ""
      wrapMode: Text.WordWrap
      color: Color.popups.text
      font.family: root.payload.language ? "monospace" : Style.font.resolvedFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: !!root.payload.attribution
      textFormat: Text.PlainText
      text: "— " + (root.payload.attribution || "")
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }
  }
}
