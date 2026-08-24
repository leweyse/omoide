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
// The ring grows INWARD rather than outward. Outward would be the more usual
// look, but MemoryCard, EventCard and RelatedCard all set `clip: true` for their
// rounded thumbnails, and every page is inside a clipping Flickable, so anything
// drawn past a card's bounds is cut off. In the events carousel, where cards sit
// 6px apart, it would also collide with its neighbour. Inward reads as the same
// two concentric lines with a gap, costs no layout, and cannot be clipped.
Rectangle {
  id: root

  property bool hasCursor: false
  property bool hot: false

  // Two vertical bars, just inside the left and right edges, instead of a full
  // ring. Named for what it draws: it started as a single left bar, and a
  // property called leftOnly that drew both sides would mislead the next reader.
  //
  // For a control -- a button, a chip, a text field -- a closed ring inside an
  // already-bordered box reads as a second frame, and on something only 24px
  // tall the two lines nearly touch. A pair of side bars brackets the control
  // without closing a second outline around it. Cards keep the ring: they are
  // big enough for it to read as depth rather than as a mistake.
  property bool sideBars: false

  // How far the bar is held off the top and bottom, so it runs alongside the
  // straight part of the edge rather than the curve.
  //
  // Capped, because a pill's radius is half its height: FilterChip sets
  // `radius: height / 2`, which leaves no straight run at all and made the bar
  // vanish. The cap keeps at least 10px of bar, so the shape degrades to a short
  // tick rather than to nothing.
  readonly property real barInset:
    Math.min(root.radius, Math.max(0, (root.height - Style.space(10)) / 2))

  // Distance from the host's edge to the ring: the host's own border plus the
  // transparent gap. `hostBorder` is stated rather than assumed because the
  // image block's frame is 2px, not 1 -- and that frame is already accent, so
  // the gap is the only thing distinguishing focused from unfocused there.
  property real gap: Style.space(2)
  property real hostBorder: 1
  readonly property real inset: root.hostBorder + root.gap

  // The surface the ring is drawn over. Stated by the caller, because the ring's
  // colour is computed from it -- see below.
  property color backdrop: Color.popups.background

  // Exclusion, computed rather than blended.
  //
  // A shader Blend cannot be used here: this item is a CHILD of the host it
  // would need to sample, and a ShaderEffectSource pointing at an ancestor
  // recurses -- Qt requires `recursive: true` for that and then samples the
  // PREVIOUS frame, which smears. But exclusion against an opaque colour has a
  // closed form: white excluded with C is 1 - C. Where the backdrop under the
  // ring is the host's own fill, this is not an approximation of the blend, it
  // is the same result arrived at arithmetically.
  //
  // The exception is a host with artwork bleeding under the ring band -- the
  // image block, which does run a real per-pixel Blend for exactly that reason.
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

  // For a host sitting on arbitrary image content. A single line can vanish into
  // a photo of the same tone; a light line paired with a dark one cannot, since
  // whichever loses contrast, the other keeps it. This is the cheap stand-in for
  // a difference blend -- see the note in ImageBlock.
  property bool twoTone: false

  Rectangle {
    visible: root.twoTone && !root.sideBars
    anchors.fill: parent
    anchors.margins: root.inset + 1
    color: "transparent"
    radius: Math.max(0, root.radius - 3)
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.55)
  }

  // The two bars, one per side.
  //
  // A pixel further in than the ring would be, because a bar sitting at the
  // ring's inset read as crowding the border it runs beside.
  //
  // Vertically each spans only the STRAIGHT run of its edge -- from the corner
  // radius to the same distance off the bottom. Running the full height put the
  // ends alongside the curve, where the border is already sweeping away and the
  // two stop looking parallel. Rounded caps for the same reason.
  //
  // A Repeater over the two sides rather than the same block written twice: the
  // pair has to stay identical, and mirroring by index is the cheapest way to
  // guarantee it.
  Repeater {
    model: root.sideBars ? 2 : 0

    delegate: Rectangle {
      required property int index

      // index 0 anchors from the left, index 1 the same distance from the right.
      x: index === 0 ? root.inset + 1
                     : root.width - root.inset - 1 - width
      y: root.barInset
      width: Math.max(1, Style.space(1))
      height: Math.max(0, root.height - root.barInset * 2)
      radius: width / 2
      color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tintAlpha)

      Behavior on color { ColorAnimation { duration: 60 } }
    }
  }

  Rectangle {
    visible: !root.sideBars
    anchors.fill: parent
    anchors.margins: root.inset
    color: "transparent"
    // The host's radius less TWO pixels, not less the full inset. Reducing by the
    // inset is the true concentric maths, but at a 6px radius it left the inner
    // corners visibly squarer than the outer ones. A single pixel keeps both
    // curves reading as the same shape while still tucking the inner one in.
    // Reducing by the full inset (3 here) made the inner corners look squarer
    // than the outer ones.
    radius: Math.max(0, root.radius - 2)
    // 1px either way: the accent border on the card is what announces focus, so
    // a heavy inner line here would just compete with it.
    border.width: 1
    border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tintAlpha)

    Behavior on border.color { ColorAnimation { duration: 60 } }
  }
}
