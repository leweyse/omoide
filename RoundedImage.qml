import QtQuick
import QtQuick.Effects
import qs.Commons

// An image with genuinely rounded corners and an accent frame.
//
// Qt's `clip` is rectangular, so a rounded border drawn over a square image
// leaves the image's corners poking outside the curve. The mask is the same
// approach the shell's image picker uses.
//
// The frame colour is a surface token (Color.accent), so it follows the theme
// rather than naming a colour of its own.
Item {
  id: root

  property string source: ""
  property int fillMode: Image.PreserveAspectCrop
  property int radius: Style.cornerRadius
  property color borderColor: Color.accent
  property int borderWidth: Math.max(1, Style.space(2))

  // Per-corner, because an image that bleeds to the edge of a rounded card
  // only needs the corners it actually touches. Default to `radius` so the
  // uniform case stays a one-liner.
  property int topLeftRadius: root.radius
  property int topRightRadius: root.radius
  property int bottomLeftRadius: root.radius
  property int bottomRightRadius: root.radius

  // Callers that want the frame to hug the picture rather than letterbox it
  // can size themselves from this.
  readonly property real sourceAspect: image.implicitHeight > 0
    ? image.implicitWidth / image.implicitHeight : 0

  Item {
    id: maskShape
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      antialiasing: true
      color: "black"
      topLeftRadius: root.topLeftRadius
      topRightRadius: root.topRightRadius
      bottomLeftRadius: root.bottomLeftRadius
      bottomRightRadius: root.bottomRightRadius
    }
  }

  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: maskShape
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

    Image {
      id: image
      anchors.fill: parent
      source: root.source
      fillMode: root.fillMode
      asynchronous: true
      cache: false
    }
  }

  // Drawn after the masked image, so the frame sits on the curve exactly.
  // Skipped entirely at zero width, for images inside a container that already
  // draws its own border.
  Rectangle {
    anchors.fill: parent
    visible: root.borderWidth > 0
    color: "transparent"
    antialiasing: true
    border.width: root.borderWidth
    border.color: root.borderColor
    topLeftRadius: root.topLeftRadius
    topRightRadius: root.topRightRadius
    bottomLeftRadius: root.bottomLeftRadius
    bottomRightRadius: root.bottomRightRadius
  }
}
