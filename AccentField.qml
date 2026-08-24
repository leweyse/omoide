import QtQuick
import qs.Commons
import qs.Ui

// A TextField whose focus border is the accent at full strength.
//
// The kit draws focus with Border.controlSpec("focus", ...), which applies
// focusBorderAlpha -- 0.25 by default -- so the accent came out at quarter
// strength and read as the same grey as an unfocused field. There is no
// per-instance way to change that alpha without editing the shell's style
// tokens, which would affect every panel, so the background is replaced here
// instead: identical to the kit's, with the focus branch at full alpha.
TextField {
  id: root

  // Where focus goes when Esc is pressed in here. Without this, Esc falls
  // through to whatever is above -- in a dialog that means closing it and
  // throwing the edit away, which is not what Esc in a text field should do.
  // A second Esc, now that the field has let go, does close the dialog.
  property Item escapeTo: null

  // Stated rather than inherited: a dialog's Tab order is only as complete as
  // its least tabbable control, and this is the one component every input in the
  // plugin goes through.
  activeFocusOnTab: true

  Keys.onEscapePressed: function (event) {
    // Only on a real press. Holding Escape auto-repeats, and each repeat
    // would dismiss another layer -- a held key unwound the whole stack.
    if (event.isAutoRepeat) { event.accepted = true; return }
    if (root.escapeTo) {
      root.escapeTo.forceActiveFocus()
      event.accepted = true
      return
    }
    // No target: leave the key UNACCEPTED so it bubbles to an ancestor. The old
    // fallback did `focus = false` and accepted it, which dropped focus into the
    // void AND swallowed the press -- nothing was focused, so no Keys handler
    // could fire, and the dialog became uncloseable however many times you hit
    // Escape.
  }

  // Every input sits inside a dialog, so the ring's backdrop is the menu
  // surface. A caller putting a field on a popups surface overrides it.
  property color ringBackdrop: Color.menu.background

  background: BorderSurface {
    color: Style.controlFill(root.activeFocus, root.hovered,
                             root.foreground, root.accent)
    borderSpec: root.activeFocus
                ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                : Border.controlSpec(root.hovered ? "hover-cursor" : "normal",
                                     root.foreground, root.accent)
    radius: Style.cornerRadius

    // Inside the background rather than as a child of the field: a TextField's
    // children draw over its text, and this has to sit behind it.
    FocusRing {
      anchors.fill: parent
      radius: Style.cornerRadius
      gap: 1
      hasCursor: root.activeFocus
      hot: false
      backdrop: root.ringBackdrop
    }
  }
}
