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
  // Keyboard cursor, driven by a page that owns its own cursor. A chip is small,
  // so it gets a focus BORDER rather than the card's ring and inner shadow,
  // which would swamp it.
  property bool hasCursor: false

  // Opt into Qt's tab order, the same way qs.Ui Button does. Needed inside a
  // dialog, where Tab walks the controls rather than a page-owned cursor -- with
  // this off, Tab skipped straight past "Add a reminder" to the buttons below.
  property bool focusable: false

  // One flag for "the keyboard is on this chip", whichever route put it there.
  readonly property bool focused:
    root.hasCursor || (root.focusable && root.activeFocus)

  signal clicked()

  activeFocusOnTab: root.focusable
  Keys.onReturnPressed: if (root.focusable) root.clicked()
  Keys.onEnterPressed: if (root.focusable) root.clicked()
  Keys.onSpacePressed: if (root.focusable) root.clicked()

  // The same padding tokens qs.Ui Button uses, so a chip and a button relate
  // rather than each having its own arbitrary inset. They differ in font size,
  // which is the intended distinction: a chip is a compact label, a button is a
  // control. Derived, not a hardcoded 26px.
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY

  height: chipLabel.implicitHeight + root.verticalPadding * 2
  width: chipLabel.implicitWidth + root.horizontalPadding * 2
  radius: Style.space(4)

  // Hover only, never focus. A fill behind the label on focus lowers contrast
  // against the text for no gain -- the accent border and the inner ring already
  // say where the keyboard is.
  readonly property bool hot: mouse.containsMouse

  color: root.outlined
         ? (root.hot
            ? Style.hoverFillFor(root.tint, root.tint, Color.urgent)
            : "transparent")
         : Style.normalFillFor(Color.popups.text, Color.accent, Color.urgent)
  // Border.flat, NOT controlSpec("focus"): controlSpec applies focusBorderAlpha,
  // which defaults to 0.25, so the accent came out at quarter strength and read
  // as the same muted grey as an unfocused chip. flat() applies no alpha.
  //
  // A filled chip has no border at rest, so this is what makes the cursor
  // visible on one; on an outlined chip it replaces the resting colour at the
  // same width, so only the colour changes.
  borderSpec: root.focused
              ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
              : (root.outlined
                 ? Border.controlSpec("normal", root.tint, root.tint)
                 : Border.none())

  // The same focus language as a card: accent on the border, a quiet ring just
  // inside it. gap 1, not 2 -- a chip is only ~26px tall, and 3px of inset would
  // start crowding the label.
  FocusRing {
    anchors.fill: parent
    radius: root.radius
    gap: 1
    hasCursor: root.focused
    hot: false
  }

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
