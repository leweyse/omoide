import QtQuick
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model

// One linked capture. Click to open it, or remove the link.
BorderSurface {
  id: root

  property var memory: ({})
  signal opened()
  signal removed()

  readonly property bool hasArt: !!(memory && memory.thumb)

  height: root.hasArt
          ? Style.space(96)
          : Math.max(Style.space(46),
                     label.implicitHeight + Style.spacing.md * 2 + Style.space(14))
  radius: Style.cornerRadius
  color: Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
  clip: true

  RoundedImage {
    anchors.fill: parent
    source: root.hasArt ? "file://" + root.memory.thumb : ""
    fillMode: Image.PreserveAspectCrop
    opacity: 0.65
    visible: root.hasArt
    borderWidth: 0
    radius: Math.max(0, Style.cornerRadius - root.borderLeft)
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: root.hasArt ? parent.bottom : undefined
    anchors.verticalCenter: root.hasArt ? undefined : parent.verticalCenter
    anchors.leftMargin: Style.spacing.md
    anchors.rightMargin: Style.spacing.md
    anchors.bottomMargin: Style.spacing.md
    spacing: Style.spacing.hairline

    Text {
      id: label
      width: parent.width
      text: Model.truncate(root.memory ? root.memory.title : "", 60)
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: Color.popups.text
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

  }

  Row {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.spacing.sm
    spacing: Style.spacing.xs
    opacity: 0.75

    PanelActionButton {
      iconText: "×"
      tooltipText: "Remove this link"
      size: Style.space(18)
      foreground: Color.popups.text
      fontFamily: Style.font.resolvedFamily
      onClicked: root.removed()
    }
  }
}
