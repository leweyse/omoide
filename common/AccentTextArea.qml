import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// AccentField's multi-line twin: wraps, grows with what is typed up to a line
// limit, then scrolls with the cursor kept in view.
//
// A separate component rather than a flag on AccentField, because the kit's
// TextField inherits Qt Quick Controls TextField, which is a TextInput and
// cannot wrap at all. Multi-line means TextArea, a different base type. What
// they share -- the accent focus border, the diagonal corner marks, the
// hover-not-focus fill, the Escape handoff -- is repeated here rather than
// factored out: two base types cannot share an ancestor, and a mixin for six
// bindings would cost more to follow than the six bindings do.
//
// Keep the two in step: a change to the focus language of one belongs in
// [[AccentField]] as well.
//
// A plain Item wrapping a Flickable, rather than a bare TextArea, so that the
// text can scroll under a frame that stays where it is. A TextArea alone does
// not follow its own cursor -- capped in height, it simply clips, and typing
// past the last visible line puts the cursor somewhere off the bottom with no
// way to see what is being written. `TextArea.flickable` is what Qt provides
// for this: it hands the text area to the Flickable, which then keeps the
// cursor rectangle on screen as it moves. The frame and the corner marks are
// out here on the scope so they frame the field rather than scrolling with its
// contents.
//
// Deliberately NOT a FocusScope. A scope is the tidy way to wrap a control, but
// it has to be a tab stop to be reachable, and then both it and the text area
// inside it are stops: Shift+Tab out of the text lands back on the scope, which
// hands focus straight back to the text, and the keyboard can never leave. The
// hand-built editor this replaced was a bare TextEdit with activeFocusOnTab in
// an ordinary container, and Tab worked; this keeps that arrangement and adds
// only the scrolling. `focusField()` stands in for the delegation a scope would
// have done.
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

  // Where focus goes when Esc is pressed in here. Without this, Esc falls
  // through to whatever is above -- in a dialog that means closing it and
  // throwing the edit away, which is not what Esc in a text field should do.
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
  // A floor as well as a cap, because the two multi-line inputs here want
  // different starting shapes. A to-do title is one line that occasionally runs
  // to three; a summary is a paragraph, and opening it one line tall would say
  // the wrong thing about what belongs in it.
  property int minLines: 1
  property int maxLines: 3

  readonly property var _borderSpec:
    Border.controlSpec(area.activeFocus ? "focus"
                                        : (area.hovered ? "hover-cursor" : "normal"),
                       root.foreground, root.accent)
  readonly property real _borderTop: Border.top(_borderSpec)
  readonly property real _borderBottom: Border.bottom(_borderSpec)

  // Measured from the font rather than from contentHeight/lineCount: while the
  // field is empty there is no line to divide by, and the ratio jitters by a
  // fraction as lines are added, which showed up as the box twitching mid-word.
  FontMetrics {
    id: metrics
    font: area.font
  }

  readonly property int shownLines:
    Math.max(root.minLines, Math.min(area.lineCount, root.maxLines))

  implicitHeight: root.verticalPadding * 2 + _borderTop + _borderBottom
                  + root.shownLines * metrics.height
  height: implicitHeight

  // The text area is the tab stop, not this wrapper -- see the note above.
  // Callers wanting to put the keyboard here by hand go through this rather
  // than forceActiveFocus(), which on the wrapper would focus the wrapper.
  function focusField() { area.forceActiveFocus() }

  // Tab, driven by hand.
  //
  // `TextArea.flickable` reparents the text area into the Flickable's content
  // item, and from in there Qt's own traversal does not find its way back out:
  // activeFocusOnTab stops the key being typed into the text, but nothing moves
  // the focus, so the field swallows Tab and the dialog's keyboard order dies at
  // it. So the component does the step itself, from the wrapper rather than from
  // the text area, which is what makes it land outside the component instead of
  // back inside it.
  //
  // The loop is the guard on that: if the chain hands back this item or the text
  // area, keep walking rather than focusing ourselves and trapping the keyboard
  // again -- the exact failure this replaces. Bounded, so a chain that only
  // contains us cannot spin.
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
    // Hover only, never focus. A fill change on focus lowers contrast against
    // the text you are about to type, and the accent border plus the corner
    // marks already say where the keyboard is.
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

      // No `focus: true`. Inside a FocusScope that would have named this the
      // scope's focused child; in a plain Item it instead propagates up to the
      // dialog's own scope and claims the keyboard the moment the field is
      // built -- which would override each dialog's choice of where to start.
      // The keyboard arrives here by Tab, by a click, or by focusField().
      wrapMode: TextArea.Wrap

      // Not optional, and not inherited from the scope. A TextEdit-derived item
      // with this off INSERTS a tab rather than moving focus, so Tab went into
      // the text and the field became a dead end for the keyboard -- the scope
      // being a tab stop only got focus in, never out. The hand-built editor
      // this component replaced carried the same line for the same reason.
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
        // Only on a real press. Holding Escape auto-repeats, and each repeat
        // would dismiss another layer -- a held key unwound the whole stack.
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (root.escapeTo) {
          root.escapeTo.forceActiveFocus()
          event.accepted = true
          return
        }
        // No target: hand the key to an ancestor. Un-accepting is NOT the
        // default here -- Qt's specific-key handlers arrive pre-accepted, so
        // simply returning swallows the press.
        event.accepted = false
      }

      // Return is left to the text. A multi-line field is where someone breaks
      // a line, and taking that key to save the dialog spends the one thing the
      // field is for -- the buttons and Ctrl-less shortcuts are where saving
      // belongs. Tab and Escape still leave.
    }

    ScrollBar.vertical: ScrollBar {
      // Present only while it means something: a field that fits its content
      // has nothing to indicate, and a permanent rail inside a one-line input
      // reads as chrome the control does not need.
      policy: flick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }
  }
}
