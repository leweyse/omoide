import QtQuick
import qs.Commons

// The Omoide mark, and its states.
//
// One idea drawn four ways: a frame (what you captured) around a dot (what it
// became). Geometry rather than a glyph, so it needs no icon font, scales with
// the bar, and takes its colours from the theme.
//
//   idle       frame + four corner points nothing happening
//   capturing  frame + corner marks       the region picker is open
//   working    frame + scan line          a capture is being enriched
//   failed     frame + hollow dot         enrichment did not complete
//
// `marked` adds a corner pip for to-dos owed today, and combines with any
// state.
Item {
  id: root

  property real iconSize: Style.bar.iconCanvas
  property color color: Color.bar.text
  property color accentColor: Color.accent
  property color urgentColor: Color.urgent
  property string mode: "idle"          // idle | capturing | working | failed
  property bool marked: false

  readonly property bool working: mode === "working"
  readonly property bool failed: mode === "failed"
  readonly property bool capturing: mode === "capturing"
  readonly property color activeColor: failed ? urgentColor
                                     : (working || capturing ? accentColor : color)

  // Every length below is quantised to whole physical pixels.
  //
  // At a fractional display scale a length that is round in logical pixels is
  // not round in physical ones, so opposite walls of the frame land on
  // different sub-pixel phases and rasterise at different weights, which reads
  // as the mark sitting off-centre. Quantised, opposite edges share a phase and
  // paint identically. The shell's glyph icons get the same from
  // Text.NativeRendering. At an integer scale dp() is a plain Math.round.
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  function dp(v) { return Math.max(1 / dpr, Math.round(v * dpr) / dpr) }

  // The frame's outer size, and the whole mark's painted extent: everything
  // else is drawn inside it, badge included.
  readonly property real frameSize: dp(iconSize * 0.78)

  // floor, not round, for every stroke weight, so the footer copy and the bar
  // copy share a weight. A stroke thickens only when a whole extra pixel fits.
  readonly property real frameBorder: dp(Math.max(1, Math.floor(iconSize / 12)))
  // The area inside the frame's stroke, with a little air so the marks read as
  // separate from it rather than thickening it.
  readonly property real innerSize: Math.max(dp(4), dp(frameSize
                                    - (frameBorder + Math.max(1, Math.round(iconSize / 16))) * 2))
  readonly property real markArm: Math.max(dp(2), dp(innerSize * 0.42))
  readonly property real markRadius: Math.max(dp(1), dp(innerSize * 0.24))
  readonly property real markStroke: dp(Math.max(1, Math.floor(iconSize / 14)))
  readonly property real pointSize: Math.max(dp(2), dp(Math.floor(iconSize * 0.14)))
  // How far each point sits in from its corner of the inner box. Proportional
  // to the inner box, so the group keeps its shape at every size.
  readonly property real pointInset: Math.max(dp(1), dp(innerSize * 0.15))
  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  // The capture frame, and the mark's silhouette.
  Rectangle {
    id: frame
    anchors.centerIn: parent
    width: root.frameSize
    height: width
    radius: Math.max(root.dp(2), root.dp(width * 0.28))
    color: "transparent"
    antialiasing: true
    border.width: root.frameBorder
    border.color: root.activeColor
    opacity: root.working ? 0.55 : 1.0

    Behavior on border.color { ColorAnimation { duration: 120 } }
  }

  // Idle: a point at each corner of the capture.
  //
  // Corner-anchored rather than centred, so no point lands on a half pixel at
  // a bar size where the frame and the mark have different parity.
  Item {
    id: points
    anchors.centerIn: frame
    width: root.innerSize
    height: root.innerSize
    visible: root.mode === "idle"

    Repeater {
      model: [
        { ax: 0, ay: 0 },   // top-left
        { ax: 1, ay: 0 },   // top-right
        { ax: 0, ay: 1 },   // bottom-left
        { ax: 1, ay: 1 }    // bottom-right
      ]

      delegate: Rectangle {
        required property var modelData

        width: root.pointSize
        height: width
        x: modelData.ax === 0 ? root.pointInset
                              : points.width - width - root.pointInset
        y: modelData.ay === 0 ? root.pointInset
                              : points.height - height - root.pointInset
        // Round, like the failed dot and the badge.
        radius: width / 2
        color: root.color
        antialiasing: true
      }
    }
  }

  // Failed: a hollow dot at the centre. Reads as "nothing came of it" without
  // needing a second symbol at 16px.
  Rectangle {
    anchors.centerIn: frame
    visible: root.failed
    width: Math.max(4, Math.round(root.iconSize * 0.28))
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, Math.floor(root.iconSize / 14))
    border.color: root.urgentColor
    antialiasing: true
  }

  // Capturing: rounded crop marks inside the frame, for what the picker is
  // about to do.
  //
  // Each corner is a clipped window onto a rounded rectangle the size of the
  // inner box, showing only that corner. A rounded L cannot be drawn from
  // rectangles directly, and this way the curve is a real corner radius rather
  // than something approximated. Nothing is centred, so there is no half-pixel
  // to chase.
  Item {
    id: marks
    anchors.centerIn: frame
    width: root.innerSize
    height: root.innerSize
    visible: root.capturing

    Repeater {
      model: [
        { ax: 0, ay: 0 },   // top-left
        { ax: 1, ay: 0 },   // top-right
        { ax: 0, ay: 1 },   // bottom-left
        { ax: 1, ay: 1 }    // bottom-right
      ]

      delegate: Item {
        required property var modelData

        width: root.markArm
        height: root.markArm
        x: modelData.ax === 0 ? 0 : marks.width - width
        y: modelData.ay === 0 ? 0 : marks.height - height
        clip: true

        Rectangle {
          width: marks.width
          height: marks.height
          x: modelData.ax === 0 ? 0 : parent.width - width
          y: modelData.ay === 0 ? 0 : parent.height - height
          radius: root.markRadius
          color: "transparent"
          antialiasing: true
          border.width: root.markStroke
          border.color: root.accentColor
        }
      }
    }
  }

  // Working: a line reading down the capture.
  //
  // A scan line rather than a spinner: it says "something is reading this
  // image", which is what enrichment actually is, and it stays inside the
  // frame so the mark's silhouette never changes. Clipped to the inner box, so
  // the line cannot draw over the frame stroke at the turns.
  Item {
    id: scan
    anchors.centerIn: frame
    width: root.innerSize
    height: root.innerSize
    visible: root.working
    clip: true

    Rectangle {
      id: scanLine
      width: parent.width
      height: root.markStroke
      radius: height / 2
      color: root.accentColor
      antialiasing: true

      SequentialAnimation on y {
        running: root.working && scan.visible
        loops: Animation.Infinite

        NumberAnimation {
          from: 0
          to: scan.height - scanLine.height
          duration: 750
          easing.type: Easing.InOutSine
        }

        NumberAnimation {
          from: scan.height - scanLine.height
          to: 0
          duration: 750
          easing.type: Easing.InOutSine
        }
      }
    }
  }

  // Open to-dos: a pip in the frame's top-right corner.
  //
  // Centred on the frame's corner and inside the icon's box, so the mark's
  // silhouette stays its frame and it still sits centred in the slot. Anchored
  // to the frame, so it holds the corner at every size.
  //
  // Haloed in the bar's own background so it stays legible over the stroke it
  // sits on.
  Rectangle {
    visible: root.marked
    anchors.horizontalCenter: frame.right
    anchors.verticalCenter: frame.top
    width: Math.max(root.dp(4), root.dp(root.iconSize * 0.34))
    height: width
    radius: width / 2
    color: Color.bar.background
    antialiasing: true

    Rectangle {
      anchors.centerIn: parent
      width: parent.width - Math.max(1, Math.floor(root.iconSize / 12)) * 2
      height: width
      radius: width / 2
      color: root.accentColor
      antialiasing: true
    }
  }
}
