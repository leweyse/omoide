import QtQuick
import qs.Commons
import qs.Ui

// A collection in the Library row: a mosaic of what is inside it, with the
// count and the name over the bottom edge.
//
// It used to reference a `cover` field the index never emitted, so every tile
// drew empty. Four thumbnails rather than sixteen: the tile is 104px, so a 4x4
// grid would give 26px cells and read as noise. 2x2 gives 52px, which is enough
// to recognise a screenshot.
BorderSurface {
  id: root

  property var collection: ({})
  signal activated()

  readonly property var thumbs: (collection && collection.thumbs) || []
  readonly property int shown: Math.min(4, root.thumbs.length)
  // 1 fills the tile, 2 split it into columns, 3 or 4 make a 2x2 with the last
  // cell left empty at 3. One formula, three sensible layouts.
  readonly property int cols: root.shown <= 1 ? 1 : 2
  readonly property int rows: root.shown <= 2 ? 1 : 2

  // One inset for the label and for the strip behind it, so they cannot drift
  // apart. sm had the count and the name pressed into the corner.
  readonly property real pad: Style.spacing.lg

  width: Style.space(104)
  height: Style.space(104)
  radius: Style.cornerRadius
  color: Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)

  Grid {
    id: mosaic
    // Inside the border, so the frame is not painted over.
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: root.borderLeft
    anchors.topMargin: root.borderTop
    width: root.width - root.borderLeft - root.borderRight
    height: root.height - root.borderTop - root.borderBottom
    columns: root.cols
    visible: root.shown > 0

    readonly property real cellW: width / root.cols
    readonly property real cellH: height / root.rows
    readonly property real inner: Math.max(0, Style.cornerRadius - root.borderLeft)

    Repeater {
      model: root.thumbs.slice(0, 4)

      delegate: RoundedImage {
        required property var modelData
        required property int index
        width: Math.round(mosaic.cellW)
        height: Math.round(mosaic.cellH)
        source: "file://" + modelData
        fillMode: Image.PreserveAspectCrop
        borderWidth: 0
        // Only the corners this cell actually touches, so the mosaic keeps the
        // tile's curve instead of poking square corners through it.
        topLeftRadius: index === 0 ? mosaic.inner : 0
        topRightRadius: (index === root.cols - 1 || root.shown === 1)
                        ? mosaic.inner : 0
        bottomLeftRadius: (root.rows === 1 && index === 0)
                          || (root.rows === 2 && index === 2) ? mosaic.inner : 0
        bottomRightRadius: (root.rows === 1 && index === root.shown - 1)
                           || (root.rows === 2 && index === 3) ? mosaic.inner : 0
      }
    }
  }

  // A strip behind the label, so the name stays readable over any screenshot.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
    anchors.bottomMargin: root.borderBottom
    height: label.implicitHeight + root.pad * 2
    visible: root.shown > 0
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g,
                   Color.popups.background.b, 0.85)
    bottomLeftRadius: Math.max(0, Style.cornerRadius - root.borderLeft)
    bottomRightRadius: Math.max(0, Style.cornerRadius - root.borderRight)
  }

  Column {
    id: label
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: root.pad
    spacing: 0

    Text {
      text: root.collection ? (root.collection.count || 0) : 0
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      text: root.collection ? (root.collection.name || "") : ""
      elide: Text.ElideRight
      color: Color.popups.text
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
