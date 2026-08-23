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
// `marked` adds a corner dot for open to-dos, and can combine with any state.
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

  readonly property int frameBorder: Math.max(1, Math.round(iconSize / 12))
  // The area inside the frame's stroke, with a little air so the marks read as
  // separate from it rather than thickening it.
  readonly property int innerSize: Math.max(4, Math.round(iconSize * 0.78)
                                    - (frameBorder + Math.max(1, Math.round(iconSize / 16))) * 2)
  readonly property int markArm: Math.max(2, Math.round(innerSize * 0.42))
  readonly property int markRadius: Math.max(1, Math.round(innerSize * 0.24))
  readonly property int markStroke: Math.max(1, Math.round(iconSize / 14))
  readonly property int pointSize: Math.max(2, Math.round(iconSize * 0.14))
  // How far each point sits in from its corner of the inner box. At the
  // corners the points crowd the frame's stroke; one pixel in gives them air
  // on the outside and reads as a group inside the frame rather than four
  // marks stuck to it.
  readonly property int pointInset: Math.max(1, Math.round(iconSize / 16))
  // Pushes the badge outward so its centre lands on the frame's corner rather
  // than half a pixel inside it. Anchored flush to the canvas the badge leans
  // in, and at this size half a pixel is visible. It overflows the optical
  // canvas by this much, which is fine: the button slot is wider and nothing
  // clips.
  readonly property int badgeNudge: Math.max(1, Math.round(iconSize / 16))

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  // The capture frame. Inset from the icon's optical box so the corner badge
  // has somewhere to sit.
  Rectangle {
    id: frame
    anchors.centerIn: parent
    width: Math.round(root.iconSize * 0.78)
    height: width
    radius: Math.max(2, Math.round(width * 0.28))
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
  // a bar size where the frame and the mark have different parity. Four 2px
  // points carry the same ink as the single 4px dot they replace, so the mark
  // keeps its weight next to the icons either side of it.
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
        // Round, like the failed dot and the badge. Every other mark in the
        // icon is a circle, so a square point read as a different kind of
        // thing rather than a smaller one.
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
    border.width: Math.max(1, Math.round(root.iconSize / 14))
    border.color: root.urgentColor
    antialiasing: true
  }

  // Capturing: rounded corner marks inside the frame -- crop marks, which is
  // what the picker is about to do.
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

  // Open to-dos. Haloed in the bar's own background so it stays legible where
  // it overlaps the frame.
  Rectangle {
    visible: root.marked
    anchors.right: parent.right
    anchors.rightMargin: -root.badgeNudge
    anchors.top: parent.top
    width: Math.max(4, Math.round(root.iconSize * 0.34))
    height: width
    radius: width / 2
    color: Color.bar.background
    antialiasing: true

    Rectangle {
      anchors.centerIn: parent
      width: parent.width - Math.max(1, Math.round(root.iconSize / 12)) * 2
      height: width
      radius: width / 2
      color: root.accentColor
      antialiasing: true
    }
  }
}
