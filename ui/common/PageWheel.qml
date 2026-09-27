import QtQuick
import qs.Commons

// The wheel step every Space page scrolls by. Flickable's own step is tuned for
// touch flicking and crawls with a mouse or touchpad; one notch here moves a
// readable chunk, clamped so it cannot overscroll. Declare it inside the page's
// Flickable with `page` set to that Flickable.
//
// A sideways row declares one with `horizontal: true` and `outer` set to the
// page it sits on. Sideways swipes move the row by the same step, and vertical
// ones scroll `outer`: an event a handler has taken is not handed on to the
// page's own handler, even when this one declines it.
WheelHandler {
  id: root

  required property Flickable page
  property bool horizontal: false
  property Flickable outer: null
  // The row's scroll bounds. A ListView's contentWidth is an estimate and its
  // origin moves, so a row that knows its exact extent passes it here.
  property real minPos: root.page.originX
  property real maxPos: root.page.originX + Math.max(0, root.page.contentWidth - root.page.width)

  // Scroll positions land on whole device pixels, counted from where the view
  // starts. A touchpad sends fractions of a notch, and a view resting between
  // pixels at a fractional scale rounds its one-pixel borders away.
  readonly property real dpr: root.page.Screen.devicePixelRatio > 0 ? root.page.Screen.devicePixelRatio : 1
  function snap(pos, lo, hi) {
    var p = lo + Math.round((Math.max(lo, Math.min(hi, pos)) - lo) * root.dpr) / root.dpr
    return p > hi ? p - 1 / root.dpr : p
  }

  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  orientation: root.horizontal ? Qt.Horizontal : Qt.Vertical

  function scrollVertically(flick, dy) {
    var limit = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = root.snap(flick.contentY - dy / 120 * Style.space(140), 0, limit)
  }

  onWheel: function (event) {
    if (!root.horizontal) {
      if (event.angleDelta.y !== 0) root.scrollVertically(root.page, event.angleDelta.y)
      return
    }
    if (Math.abs(event.angleDelta.x) <= Math.abs(event.angleDelta.y)) {
      if (root.outer) root.scrollVertically(root.outer, event.angleDelta.y)
      return
    }
    if (root.maxPos - root.minPos < 0.5) return
    root.page.contentX = root.snap(root.page.contentX - event.angleDelta.x / 120 * Style.space(140),
                                   root.minPos, root.maxPos)
  }
}
