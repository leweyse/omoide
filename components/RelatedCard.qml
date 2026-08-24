import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model

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
  // The outline-button border, not popups.border -- that token defaults to the
  // ACCENT, so an accent focus ring was invisible against every unfocused card.
  // Accent on focus. The width does NOT change -- a card measures its height
  // as content plus border widths, so a thicker focus border would resize the
  // card and reflow the grid on every arrow key.
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
    radius: Math.max(0, Style.cornerRadius - root.borderLeft)
  }

  FocusRing {
    anchors.fill: parent
    radius: root.radius
    hasCursor: root.hasCursor
    // Artwork bleeds under the ring on this card, so it gets the dark
    // companion line: whichever of the two loses contrast against the
    // thumbnail, the other keeps it.
    twoTone: true
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
