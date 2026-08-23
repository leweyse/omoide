import QtQuick
import qs.Commons
import qs.Ui

// The heading here is the MODEL's, not a label: it describes these specific
// items ("Key Interior Design Trends for 2026"), so it lives in the payload.
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
  heading: payload.heading || ""

  Column {
    width: parent.width
    spacing: Style.spacing.sm

    Repeater {
      model: root.payload.items || []

      delegate: Row {
        required property var modelData
        required property int index
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          text: root.payload.ordered ? (index + 1) + "." : "·"
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width - Style.space(14)
          wrapMode: Text.WordWrap
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
          textFormat: Text.StyledText
          text: modelData.label && modelData.label.length
                ? "<b>" + modelData.label + ":</b> " + modelData.text
                : (modelData.text || "")
        }
      }
    }
  }
}
