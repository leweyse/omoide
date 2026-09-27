import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// AccentField's multi-line twin: wraps, grows with what is typed up to a line
// limit, then scrolls with the cursor kept in view.
//
// A separate component rather than a flag on AccentField: the kit's TextField
// is a TextInput and cannot wrap, so multi-line needs TextArea, a different
// base type. The focus border, corner marks, hover-only fill and Escape handoff
// are repeated rather than shared, since the two base types have no common
// ancestor. A change to the focus language of one belongs in AccentField too.
//
// A plain Item wrapping a Flickable, so the text scrolls under a frame that
// stays put. A capped TextArea alone clips and does not follow its cursor;
// `TextArea.flickable` hands it to the Flickable, which keeps the cursor
// rectangle on screen. The frame and corner marks live on the wrapper so they
// do not scroll.
//
// Deliberately not a FocusScope. A scope must be a tab stop to be reachable,
// and then Shift+Tab out of the text lands on the scope, which hands focus
// straight back: the keyboard can never leave. `focusField()` stands in for
// the delegation a scope would do.
Item {
  id: root

  property alias text: area.text
  property alias placeholderText: area.placeholderText
  property alias font: area.font
  property alias cursorPosition: area.cursorPosition
  property alias readOnly: area.readOnly
  property alias hovered: area.hovered
  property alias selectByMouse: area.selectByMouse
  property alias lineCount: area.lineCount

  // Where focus goes when Esc is pressed in here. Without it, Esc reaches the
  // enclosing dialog and closes it, discarding the edit.
  property Item escapeTo: null

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property color ringBackdrop: Color.menu.background

  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY

  // The band it is allowed to occupy: it opens at `minLines`, grows with what
  // is typed, and at `maxLines` stops growing and scrolls instead.
  //
  // A floor as well as a cap: a to-do title starts as one line, a summary as a
  // paragraph.
  property int minLines: 1
  property int maxLines: 3

  readonly property var _borderSpec:
    Border.controlSpec(area.activeFocus ? "focus"
                                        : (area.hovered ? "hover-cursor" : "normal"),
                       root.foreground, root.accent)
  readonly property real _borderTop: Border.top(_borderSpec)
  readonly property real _borderBottom: Border.bottom(_borderSpec)

  // Measured from the font rather than contentHeight/lineCount, which has no
  // line to divide by while empty and jitters as lines are added.
  FontMetrics {
    id: metrics
    font: area.font
  }

  readonly property int shownLines:
    Math.max(root.minLines, Math.min(area.lineCount, root.maxLines))

  implicitHeight: root.verticalPadding * 2 + _borderTop + _borderBottom
                  + root.shownLines * metrics.height
  height: implicitHeight

  // The text area is the tab stop, not this wrapper. Callers focus the field
  // through this; forceActiveFocus() on the wrapper would focus the wrapper.
  function focusField() { area.forceActiveFocus() }

  // Tab, driven by hand.
  //
  // `TextArea.flickable` reparents the text area into the Flickable's content
  // item, and Qt's own traversal does not find its way back out: the field
  // would swallow Tab. So the step starts from the wrapper, which lands it
  // outside the component.
  //
  // The loop skips this item and the text area if the chain hands them back,
  // so focus never returns inside. Bounded, so a chain holding only us cannot
  // spin.
  function moveFocus(forward) {
    var from = root
    for (var i = 0; i < 16; i++) {
      var next = from.nextItemInFocusChain(forward)
      if (!next || next === from) return false
      if (next !== root && next !== area) {
        next.forceActiveFocus()
        return true
      }
      from = next
    }
    return false
  }

  readonly property alias fieldHasFocus: area.activeFocus

  BorderSurface {
    anchors.fill: parent
    // Hover only, never focus. A focus fill lowers contrast against the text
    // being typed, and the accent border and corner marks already show focus.
    color: Style.controlFill(false, area.hovered, root.foreground, root.accent)
    borderSpec: area.activeFocus
                ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                : Border.controlSpec(area.hovered ? "hover-cursor" : "normal",
                                     root.foreground, root.accent)
    radius: Style.cornerRadius

    FocusRing {
      diagonalCorners: true
      anchors.fill: parent
      radius: Style.cornerRadius
      gap: 1
      hasCursor: area.activeFocus
      hot: false
      backdrop: root.ringBackdrop
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.topMargin: root._borderTop
    anchors.bottomMargin: root._borderBottom
    clip: true
    contentWidth: width
    contentHeight: area.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    // Only once there is something to scroll, so a one-line field does not
    // swallow a drag that belongs to the dialog behind it.
    interactive: contentHeight > height

    // The attachment is what makes the Flickable keep the cursor in view.
    TextArea.flickable: TextArea {
      id: area

      // No `focus: true`. In a plain Item it propagates to the dialog's scope
      // and claims the keyboard when the field is built, overriding where each
      // dialog chooses to start. The keyboard arrives by Tab, a click, or
      // focusField().
      wrapMode: TextArea.Wrap

      // Required. A TextEdit-derived item with this off inserts a tab instead
      // of moving focus, and the field becomes a dead end for the keyboard.
      activeFocusOnTab: true

      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: root.foreground
      selectionColor: root.selectionTint
      selectedTextColor: root.foreground
      placeholderTextColor: Qt.darker(root.foreground, 1.6)

      // The frame is drawn by the scope, so the text area brings none of its
      // own -- one would scroll away with the text.
      background: null
      leftPadding: root.horizontalPadding + Border.left(root._borderSpec)
      rightPadding: root.horizontalPadding + Border.right(root._borderSpec)
      topPadding: root.verticalPadding
      bottomPadding: root.verticalPadding

      // Ahead of the item, so Tab is intercepted before the text area can
      // treat it as input or as a traversal it cannot complete.
      Keys.priority: Keys.BeforeItem

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          // Shift+Tab usually arrives as Backtab, but not on every layout, so
          // the modifier is checked too.
          var forward = event.key === Qt.Key_Tab
                        && !(event.modifiers & Qt.ShiftModifier)
          root.moveFocus(forward)
          event.accepted = true
        }
      }

      Keys.onEscapePressed: function (event) {
        // Only on a real press. Each auto-repeat of a held Escape would
        // dismiss another layer.
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (root.escapeTo) {
          root.escapeTo.forceActiveFocus()
          event.accepted = true
          return
        }
        // No target: hand the key to an ancestor. Qt's specific-key handlers
        // arrive pre-accepted, so returning alone would swallow the press.
        event.accepted = false
      }

      // Return is left to the text: it breaks a line here, and saving belongs
      // to the dialog's buttons. Tab and Escape still leave.
    }

    ScrollBar.vertical: ScrollBar {
      // Shown only while the content overflows.
      policy: flick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }
  }
}
