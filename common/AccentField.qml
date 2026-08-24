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
    // No target: hand the key to an ancestor. Un-accepting is NOT the default
    // here -- Qt's specific-key handlers arrive pre-accepted
    // (QQuickKeysAttached::keyPressed calls setAccepted(true) before invoking
    // onEscapePressed), so simply returning swallows the press. That is what
    // made Escape do nothing at all in the compose overlay, whose note field
    // has no escapeTo and relies on the overlay's own catcher.
    //
    // Not `focus = false` either: that dropped focus into the void as well as
    // eating the key, leaving nothing focused for any Keys handler to fire on.
    event.accepted = false
  }

  // Every input sits inside a dialog, so the ring's backdrop is the menu
  // surface. A caller putting a field on a popups surface overrides it.
  property color ringBackdrop: Color.menu.background

  background: BorderSurface {
    // Hover only, never focus. A fill change on focus lowers contrast against
    // the text you are about to type, and the accent border plus the inner ring
    // already say where the keyboard is. Passing false for `focused` keeps the
    // kit's hover and resting fills untouched.
    color: Style.controlFill(false, root.hovered,
                             root.foreground, root.accent)
    borderSpec: root.activeFocus
                ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                : Border.controlSpec(root.hovered ? "hover-cursor" : "normal",
                                     root.foreground, root.accent)
    radius: Style.cornerRadius

    // Inside the background rather than as a child of the field: a TextField's
    // children draw over its text, and this has to sit behind it.
    FocusRing {
      sideBars: true
      anchors.fill: parent
      radius: Style.cornerRadius
      gap: 1
      hasCursor: root.activeFocus
      hot: false
      backdrop: root.ringBackdrop
    }
  }
}
