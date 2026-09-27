import QtQuick
import qs.Commons
import "../common"

// The capture itself.
//
// Not a BlockCard: the image draws its own accent frame, and the card's border
// would put a second frame around it. This block is just the picture, sized to
// its own aspect so the frame hugs it.
Item {
  id: root

  property var payload: ({})
  property var service: null

  // Not a BlockCard, so it declares the two fields the renderer binds onto
  // every block itself. Unused here: an image is the capture, not something
  // the agent wrote, so there is nothing to edit.
  property string blockId: ""
  property string blockType: ""
  property bool hasCursor: false
  signal previewRequested(string path)

  // The stored dimensions when we have them, falling back to what the loaded
  // image reports. Having them up front means the page does not reflow once
  // the pixels arrive.
  readonly property real aspect: root.payload.aspect > 0 ? root.payload.aspect
                                                         : shot.sourceAspect
  readonly property real maxHeight: Style.space(340)

  // A gutter the picture never crosses, taken off both sides so it stays
  // centred. The memory page floats its action buttons over the top right of
  // its first block, which is this one, so a wide capture must not draw under
  // them. The page sets this, because the page knows the buttons are there.
  property real sideGutter: 0

  // The widest the picture may draw. Floored, so a narrow dialog does not let
  // the gutter eat the capture it is there to keep clear of.
  readonly property real maxWidth:
    Math.max(Style.space(200), root.width - root.sideGutter * 2)

  readonly property real drawHeight: Math.min(
    root.maxHeight,
    root.aspect > 0 ? root.maxWidth / root.aspect : root.maxWidth * 0.56)
  readonly property real drawWidth: root.aspect > 0
    ? Math.min(root.maxWidth, root.drawHeight * root.aspect) : root.maxWidth

  width: parent ? parent.width : 0
  height: shot.height

  // Sized and positioned to the picture, not the block: the block spans the
  // page width while the image is centred at its own aspect, so a ring on the
  // block bounds would float in the margin beside the photo.
  FocusRing {
    x: shot.x
    y: shot.y
    width: shot.width
    height: shot.height
    radius: Style.cornerRadius
    // RoundedImage draws an accent frame of its own, so the ring has to clear
    // it, or focused and unfocused look the same.
    hostBorder: Math.max(1, Style.space(2))
    // Corner marks: their line-in-halo pair keeps contrast against whatever
    // the user captured, which no single fixed line can promise.
    cornersOnly: true
    hasCursor: root.hasCursor
    hot: false
  }

  RoundedImage {
    id: shot
    // Bounded by height, never by crop: a tall capture gets narrower rather
    // than losing its top and bottom. Centred, so a portrait selection sits in
    // the middle of the page.
    x: Math.round((parent.width - width) / 2)
    width: Math.round(root.drawWidth)
    height: Math.round(root.drawHeight)
    source: root.payload.thumb ? "file://" + root.payload.thumb
          : (root.payload.path ? "file://" + root.payload.path : "")
    fillMode: Image.PreserveAspectCrop

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      // Preview, not edit: clicking a picture should show it, and the editor
      // is offered from there.
      onClicked: if (root.payload.path) root.previewRequested(root.payload.path)
    }
  }
}
