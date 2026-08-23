import QtQuick
import qs.Commons
import qs.Ui

// One chip in a row of them.
//
// Its own component because the Collections row had three: a collection this
// memory is in, one it could be filed into, and the control that opens the name
// field. Two were hand-built Rectangles at caption size and the third was a
// Button with control-sized padding, so they sat at different heights in the
// same Flow.
//
// Filled reads as a fact, outlined as an offer.
BorderSurface {
  id: root

  property string label: ""
  property color tint: Color.popups.text
  property bool outlined: false
  property bool interactive: false

  signal clicked()

  // The same padding tokens qs.Ui Button uses, so a chip and a button relate
  // rather than each having its own arbitrary inset. They differ in font size,
  // which is the intended distinction: a chip is a compact label, a button is a
  // control. Derived, not a hardcoded 26px.
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY

  height: chipLabel.implicitHeight + root.verticalPadding * 2
  width: chipLabel.implicitWidth + root.horizontalPadding * 2
  radius: Style.space(4)

  color: root.outlined
         ? (mouse.containsMouse
            ? Style.hoverFillFor(root.tint, root.tint, Color.urgent)
            : "transparent")
         : Style.normalFillFor(Color.popups.text, Color.accent, Color.urgent)
  borderSpec: root.outlined
              ? Border.controlSpec("normal", root.tint, root.tint)
              : Border.none()

  Text {
    id: chipLabel
    anchors.centerIn: parent
    text: root.label
    color: root.tint
    font.family: Style.font.resolvedFamily
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: root.interactive
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
