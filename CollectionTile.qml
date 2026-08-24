import QtQuick
import qs.Commons
import qs.Ui

// A collection: its count, its name, and one cover.
//
// Was a 2x2 mosaic of up to four thumbnails with the name on a plate over the
// top. Two problems, both structural rather than cosmetic: the plate covered 40%
// of the tile, so the bottom row of any two-row grid was a 10px sliver; and at
// 104px wide a quarter-tile cell is 51px, where a screenshot is texture rather
// than something you can recognise.
//
// One cover beside the text fixes both. The count sits at the top and the name at
// the bottom, so a one-word name and a three-line one both look deliberate.
BorderSurface {
  id: root

  property var collection: ({})
  property bool hasCursor: false
  signal activated()

  readonly property var thumbs: (collection && collection.thumbs) || []
  readonly property string cover: root.thumbs.length > 0 ? root.thumbs[0] : ""

  readonly property real pad: Style.spacing.xxl

  // Wide, not square: the name needs room to wrap to two or three lines beside
  // the cover rather than being elided at every collection worth naming.
  width: Style.space(216)
  height: Style.space(112)
  radius: Style.cornerRadius
  color: Color.popups.background
  // Accent on focus, and NOT popups.border at rest -- that token defaults to the
  // accent, so an accent focus border was invisible against every unfocused
  // card. The width never changes, so nothing reflows.
  borderSpec: root.hasCursor
              ? Border.flat(Color.accent, 1)
              : Border.controlSpec("normal", Color.popups.text, Color.accent)

  FocusRing {
    anchors.fill: parent
    radius: root.radius
    hasCursor: root.hasCursor
    hot: hoverArea.containsMouse
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  // The cover, inset on all sides so the card's own frame stays visible around
  // it. Portrait-ish, which is what a cropped capture survives best.
  RoundedImage {
    id: art
    visible: root.cover.length > 0
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: root.pad
    width: Math.round(root.width * 0.34)
    radius: Style.space(5)
    borderWidth: 0
    source: "file://" + root.cover
    fillMode: Image.PreserveAspectCrop
  }

  Text {
    id: countText
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: root.pad
    text: root.collection ? (root.collection.count || 0) : 0
    color: Color.muted
    font.family: Style.font.resolvedFamily
    font.pixelSize: Style.font.caption
  }

  // Bottom-aligned, so the name grows upward into the space the count leaves
  // rather than pushing it around.
  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.pad
    anchors.bottomMargin: root.pad
    anchors.right: art.visible ? art.left : parent.right
    anchors.rightMargin: root.pad
    text: root.collection ? (root.collection.name || "") : ""
    wrapMode: Text.WordWrap
    maximumLineCount: 3
    elide: Text.ElideRight
    lineHeight: 1.15
    color: Color.popups.text
    font.family: Style.font.resolvedFamily
    font.pixelSize: Style.font.subtitle
  }
}
