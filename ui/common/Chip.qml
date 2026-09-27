import QtQuick
import qs.Commons
import qs.Ui

// One chip in a row of them, at one height whatever it holds: a collection
// the memory is in, one it could be filed into, or a control.
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
  // dialog, where Tab walks the controls rather than a page-owned cursor.
  property bool focusable: false

  // One flag for "the keyboard is on this chip", whichever route put it there.
  readonly property bool focused:
    root.hasCursor || (root.focusable && root.activeFocus)

  signal clicked()

  activeFocusOnTab: root.focusable
  Keys.onReturnPressed: if (root.focusable) root.clicked()
  Keys.onEnterPressed: if (root.focusable) root.clicked()
  Keys.onSpacePressed: if (root.focusable) root.clicked()

  // The same padding tokens qs.Ui Button uses, so a chip and a button share an
  // inset and differ only in font size.
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY

  height: chipLabel.implicitHeight + root.verticalPadding * 2
  width: chipLabel.implicitWidth + root.horizontalPadding * 2
  radius: Style.cornerRadius

  // Hover only, never focus. A focus fill lowers contrast against the label,
  // and the accent border and inner ring already show focus.
  readonly property bool hot: mouse.containsMouse

  color: root.outlined
         ? (root.hot
            ? Style.hoverFillFor(root.tint, root.tint, Color.urgent)
            : "transparent")
         : Style.normalFillFor(Color.popups.text, Color.accent, Color.urgent)
  // Border.flat, not controlSpec("focus"), which applies focusBorderAlpha and
  // makes the accent hard to tell from an unfocused chip.
  //
  // A filled chip has no border at rest, so this is what shows the cursor on
  // one; on an outlined chip it replaces the resting colour at the same width.
  borderSpec: root.focused
              ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
              : (root.outlined
                 ? Border.controlSpec("normal", root.tint, root.tint)
                 : Border.none())

  // The same focus language as a card: accent on the border, a quiet ring just
  // inside it. Gap 1, because a chip is short and a wider inset crowds the label.
  FocusRing {
    diagonalCorners: true
    anchors.fill: parent
    radius: root.radius
    gap: 1
    hasCursor: root.focused
    hot: false
  }

  Text {
    id: chipLabel
    anchors.centerIn: parent
    // A chip's label is a tag or a collection name, so it is model output or
    // something the user typed. Neither ever wants markup.
    textFormat: Text.PlainText
    text: root.label
    color: root.tint
    font.family: Style.font.resolvedFamily
    font.pixelSize: Style.font.body
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
