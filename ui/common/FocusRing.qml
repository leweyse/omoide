import QtQuick
import qs.Commons

// The hover and keyboard-focus indicator for a card: a ring set in from the
// card's own border, with a transparent gap between the two.
//
// An overlay, never a change to the card's borderSpec. A card's height is
// measured as its content plus its border widths, so widening the border on
// focus would resize the card and reflow the whole masonry layout on every
// arrow key. Painted on top, this cannot move anything.
//
// The ring grows inward. MemoryCard, EventCard and RelatedCard set
// `clip: true` for their rounded thumbnails, every page sits in a clipping
// Flickable, and carousel cards sit close together, so anything drawn past a
// card's bounds would be cut off or collide with a neighbour.
Rectangle {
  id: root

  property bool hasCursor: false
  property bool hot: false

  // Two corner marks, top-left and bottom-right, instead of a closed ring: the
  // control-sized counterpart to `cornersOnly`. On a button, chip or field a
  // closed ring inside the border reads as a second frame, and four marks
  // around something that small read as a box.
  property bool diagonalCorners: false

  // Four corner marks instead of a closed ring, the same idiom as the bar
  // icon's capturing state, for hosts whose content is itself a picture. The
  // stroke is a pixel heavier than the ring's, because four short arcs carry
  // less ink than a closed outline.
  property bool cornersOnly: false


  // Distance from the host's edge to the ring: the host's own border plus the
  // transparent gap. `hostBorder` is stated because the image block's frame is
  // 2px and already accent, so the gap is all that marks focus there.
  property real gap: Style.space(2)
  property real hostBorder: 1
  // A control's marks sit one pixel further in, so short marks read as
  // separate from the border rather than growing out of it.
  readonly property real inset: root.hostBorder + root.gap
                                + (root.diagonalCorners ? Style.space(1) : 0)

  // The surface the ring is drawn over. Stated by the caller, because the
  // ring's colour is computed from it.
  property color backdrop: Color.popups.background

  // Exclusion, computed rather than blended.
  //
  // A shader Blend cannot be used: this item is a child of the host it would
  // sample, and a ShaderEffectSource on an ancestor needs `recursive: true`,
  // which samples the previous frame and smears. Exclusion against an opaque
  // colour has a closed form, white excluded with C is 1 - C, so over the
  // host's own fill this is exact. Over artwork it is an approximation, which
  // the corner marks' edging covers.
  readonly property color tint:
    Qt.rgba(1 - root.backdrop.r, 1 - root.backdrop.g, 1 - root.backdrop.b, 1)

  readonly property real tintAlpha: root.hasCursor ? 1.0 : 0.55

  // The card's border is the outer line; this Rectangle only hosts the ring.
  color: "transparent"
  border.width: 0
  visible: root.hasCursor || root.hot
  // Above the card's content, which includes a full-bleed thumbnail: drawn
  // underneath, the ring would vanish along the card's top edge.
  z: 10

  // For a host on arbitrary image content. A single line can vanish into a
  // photo of the same tone; a light line paired with a dark one cannot, since
  // whichever loses contrast, the other keeps it. The cheap stand-in for a
  // difference blend.
  property bool twoTone: false

  Rectangle {
    visible: root.twoTone && !root.cornersOnly && !root.diagonalCorners
    anchors.fill: parent
    anchors.margins: root.inset + 1
    color: "transparent"
    radius: Math.max(0, root.radius - 3)
    border.width: 1
    // The backdrop, not a hardcoded black, so the two lines stay inverses of
    // each other in a light theme too.
    border.color: Qt.rgba(root.backdrop.r, root.backdrop.g,
                          root.backdrop.b, 0.55)
  }

  Rectangle {
    visible: !root.cornersOnly && !root.diagonalCorners
    anchors.fill: parent
    anchors.margins: root.inset
    color: "transparent"
    // The host's radius less two pixels, not less the full inset. True
    // concentric maths leaves the inner corners visibly squarer than the outer
    // ones at small radii.
    radius: Math.max(0, root.radius - 2)
    // 1px either way: the accent border on the card is what announces focus, so
    // a heavy inner line here would just compete with it.
    border.width: 1
    border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tintAlpha)

    Behavior on border.color { ColorAnimation { duration: 60 } }
  }

  // The corner marks. Each is a clipped window onto a rectangle the size of
  // the full ring, showing only its corner. A rounded L cannot be drawn from
  // rectangles directly, and this way the curve is the ring's real corner
  // radius. Same construction as the capturing state of SpaceIcon.
  //
  // Three strokes per mark: the tint line with a 1px edging of the backdrop's
  // colour on either side. Line and edging are inverses, so on any artwork,
  // theme or colour vision one of them separates the mark from the content;
  // luminance does the work, never hue. Keep the edgings thin: a wide halo
  // swallows the curve. A per-pixel inversion does not work, because exclusion
  // maps mid-grey to mid-grey.
  Item {
    id: corners
    visible: root.cornersOnly || root.diagonalCorners
    anchors.fill: parent

    Item {
      id: cornerFrame
      anchors.fill: parent
      anchors.margins: root.inset

      // The host's radius less three: close enough to concentric to read as
      // the host's own corner, without bulging rounder than the curve the mark
      // sits inside.
      readonly property real ringRadius: Math.max(0, root.radius - 3)
      // Past the curve and onto the straight edge, so the mark reads as a
      // corner of the ring rather than a dot. Capped so opposite corners can
      // never meet on a small host.
      //
      // Shorter on a control than on a card, by length rather than weight, so
      // the mark stays a corner and does not become a bracket around the label.
      readonly property real armRun:
        root.diagonalCorners ? Style.space(4) : Style.space(6)
      readonly property real arm:
        Math.min(ringRadius + armRun, Math.min(width, height) / 2)

      Repeater {
        // Four corners frame a card; the diagonal pair marks a control without
        // enclosing it. Opposite corners rather than adjacent ones, so the two
        // marks describe the whole shape between them.
        model: root.diagonalCorners
               ? [
                 { ax: 0, ay: 0 },   // top-left
                 { ax: 1, ay: 1 }    // bottom-right
               ]
               : [
                 { ax: 0, ay: 0 },   // top-left
                 { ax: 1, ay: 0 },   // top-right
                 { ax: 0, ay: 1 },   // bottom-left
                 { ax: 1, ay: 1 }    // bottom-right
               ]

        delegate: Item {
          required property var modelData

          // One pixel of slack around the window, so the outer edging's curve
          // is not clipped flat at the frame boundary.
          readonly property real pad: 1
          // The frame's origin, in this window's coordinates.
          readonly property real fx: modelData.ax === 0
                                     ? pad : cornerFrame.arm + pad - cornerFrame.width
          readonly property real fy: modelData.ay === 0
                                     ? pad : cornerFrame.arm + pad - cornerFrame.height

          width: cornerFrame.arm + pad * 2
          height: cornerFrame.arm + pad * 2
          x: (modelData.ax === 0 ? 0 : cornerFrame.width - cornerFrame.arm) - pad
          y: (modelData.ay === 0 ? 0 : cornerFrame.height - cornerFrame.arm) - pad
          clip: true

          Rectangle {   // outer edging
            x: parent.fx - 1
            y: parent.fy - 1
            width: cornerFrame.width + 2
            height: cornerFrame.height + 2
            radius: cornerFrame.ringRadius + 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.backdrop.r, root.backdrop.g,
                                  root.backdrop.b, root.tintAlpha)
          }

          Rectangle {   // inner edging
            x: parent.fx + 2
            y: parent.fy + 2
            width: cornerFrame.width - 4
            height: cornerFrame.height - 4
            radius: Math.max(0, cornerFrame.ringRadius - 2)
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.backdrop.r, root.backdrop.g,
                                  root.backdrop.b, root.tintAlpha)
          }

          Rectangle {   // the line
            x: parent.fx
            y: parent.fy
            width: cornerFrame.width
            height: cornerFrame.height
            radius: cornerFrame.ringRadius
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tintAlpha)

            Behavior on border.color { ColorAnimation { duration: 60 } }
          }
        }
      }
    }
  }
}
