import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model
import "../common/Radii.js" as Radii

// One linked capture. Click to open it, or remove the link.
BorderSurface {
  id: root

  property var memory: ({})
  property bool hasCursor: false
  signal opened()
  signal removed()

  readonly property bool hasArt: !!(memory && memory.thumb)

  height: root.hasArt
          ? Style.space(96)
          : Math.max(Style.space(46),
                     label.implicitHeight + Style.spacing.lg * 2 + Style.space(14))
  radius: Style.cornerRadius
  color: Color.popups.background
  // Accent on focus; at rest the outline-button border, not popups.border,
  // which defaults to the accent and would hide the focus border. The width
  // never changes: a card's height includes its border widths, so a thicker
  // focus border would reflow the grid on every arrow key.
  borderSpec: root.hasCursor
              ? Border.flat(Color.accent, 1)
              : Border.controlSpec("normal", Color.popups.text, Color.accent)
  clip: true

  RoundedImage {
    anchors.fill: parent
    source: root.hasArt ? "file://" + root.memory.thumb : ""
    fillMode: Image.PreserveAspectCrop
    opacity: 0.65
    visible: root.hasArt
    borderWidth: 0
    radius: Radii.nested(Style.cornerRadius, root.borderLeft)
  }

  FocusRing {
    anchors.fill: parent
    radius: root.radius
    cornersOnly: true
    hasCursor: root.hasCursor
    hot: relatedHover.containsMouse
  }

  MouseArea {
    id: relatedHover
    hoverEnabled: true
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: root.hasArt ? parent.bottom : undefined
    anchors.verticalCenter: root.hasArt ? undefined : parent.verticalCenter
    anchors.leftMargin: Style.spacing.lg
    anchors.rightMargin: Style.spacing.lg
    anchors.bottomMargin: Style.spacing.lg
    spacing: Style.spacing.xxs

    Text {
      id: label
      width: parent.width
      textFormat: Text.PlainText
      text: Model.truncate(root.memory ? root.memory.title : "", 60)
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: Color.popups.text
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.body
    }

  }

  Row {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.sm
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
