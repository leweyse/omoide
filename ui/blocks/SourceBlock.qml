import QtQuick
import Quickshell
import qs.Commons
import "../MemoryModel.js" as Model

// Category chip, domain and byline. No favicon: fetching one needs the
// network, so this shows the domain the capture already carries.
BlockCard {
  id: root
  property var payload: ({})
  property var service: null

  Column {
    width: parent.width
    spacing: Style.spacing.sm

    Row {
      spacing: Style.spacing.md
      visible: !!(root.payload.chip || root.payload.byline)

      Rectangle {
        visible: !!root.payload.chip
        height: Style.space(18)
        width: chipText.implicitWidth + Style.spacing.lg
        radius: Style.cornerRadius
        color: Style.selectedFillFor(Color.popups.text, Color.accent, Color.urgent)
        Text {
          id: chipText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.payload.chip || ""
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.payload.byline || ""
        color: Color.muted
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.body
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.payload.domain || ""
      color: Color.popups.text
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.subtitle
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: Model.truncate(root.payload.url || "", 90)
      elide: Text.ElideRight
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.body

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.payload.url)
          Quickshell.execDetached(["omarchy", "launch", "browser", root.payload.url])
      }
    }
  }
}
