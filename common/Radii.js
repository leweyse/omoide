.pragma library

// Corner radius for a surface nested inside a bordered card.
//
// The concentric rule: an inner edge sitting one border width inside an outer
// curve needs that much less radius to stay parallel to it. A card with a
// 6px outer radius and a 2px border therefore wants 4 on whatever fills it.
//
// Do not shave an extra pixel off to tighten the seam. BorderSurface paints
// its rounded corner itself, and the card's `clip: true` clips children to its
// bounding rectangle, not to that curve. An inner surface any squarer than the
// curve paints over the rounding and leaves a hard notch inside the border.
//
// Not for containment radii either. A scrim or clip laid inside a card wants a
// radius that matches or exceeds the curve it sits in, so its own corners stay
// inside it. SpaceWindow's `cardRadius` is that case and deliberately keeps
// its own arithmetic.
function nested(outer, border) {
  return Math.max(0, outer - border)
}
