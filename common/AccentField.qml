import QtQuick
import qs.Commons
import qs.Ui

// A TextField whose focus border is the accent at full strength.
//
// The kit's Border.controlSpec("focus", ...) applies focusBorderAlpha, which
// makes a focused field hard to tell from an unfocused one, and the alpha is a
// shell-wide style token. The background is therefore the kit's own, with the
// focus branch drawn at full alpha.
TextField {
  id: root

  // Where focus goes when Esc is pressed in here. Without it, Esc reaches the
  // enclosing dialog and closes it, discarding the edit. A second Esc, once the
  // field has let go, does close the dialog.
  property Item escapeTo: null

  // Stated rather than inherited: a dialog's Tab order is only as complete as
  // its least tabbable control, and this is the one component every input in the
  // plugin goes through.
  activeFocusOnTab: true

  Keys.onEscapePressed: function (event) {
    // Only on a real press. Each auto-repeat of a held Escape would dismiss
    // another layer.
    if (event.isAutoRepeat) { event.accepted = true; return }
    if (root.escapeTo) {
      root.escapeTo.forceActiveFocus()
      event.accepted = true
      return
    }
    // No target: hand the key to an ancestor. Qt's specific-key handlers
    // arrive pre-accepted (QQuickKeysAttached::keyPressed calls
    // setAccepted(true) before onEscapePressed), so returning alone would
    // swallow the press. The compose overlay's note field relies on this.
    //
    // Not `focus = false`: that eats the key and leaves nothing focused for any
    // Keys handler to fire on.
    event.accepted = false
  }

  // Every input sits inside a dialog, so the ring's backdrop is the menu
  // surface. A caller putting a field on a popups surface overrides it.
  property color ringBackdrop: Color.menu.background

  background: BorderSurface {
    // Hover only, never focus. A focus fill lowers contrast against the text
    // being typed, and the accent border and inner ring already show focus.
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
      diagonalCorners: true
      anchors.fill: parent
      radius: Style.cornerRadius
      gap: 1
      hasCursor: root.activeFocus
      hot: false
      backdrop: root.ringBackdrop
    }
  }
}
