import QtQuick
import qs.Commons
import qs.Ui

// A button for the plugin's dialogs, where focus shows in the outline and
// never in the fill.
//
// Two departures from a bare qs.Ui Button, both of which every dialog here was
// already writing out by hand:
//
// The fill. Button ranks a focus FILL above hover in its colour precedence, so
// tabbing onto a control both lit its border and washed a panel of colour in
// behind the label. On something already outlined that is one signal too many:
// the border colour and the ring just inside it have said where the keyboard
// is, and the fill only spends contrast against the text sitting on top of it.
// Worse on the primary button, whose selected fill it replaced -- so Save
// stopped looking primary at the moment it was focused. Chip.qml already
// follows this rule for chips; this is the same rule for buttons.
//
// The border. Border.controlSpec("focus") applies focusBorderAlpha, which
// defaults to 0.25, so the accent arrived at quarter strength and read as the
// same muted grey as an unfocused control. Border.flat applies no alpha.
//
// Pressed folds into hover rather than keeping its own fill: Button holds that
// state on an internal MouseArea a derived type cannot read, and a pointer that
// is pressing is also hovering, so the control still answers the click.
//
// `selected` still fills, and is what marks the primary action.
Button {
  id: root

  bordered: true

  color: root.hot      ? Style.hoverFillFor(root.foreground, root.accent)
       : root.selected ? Style.selectedFillFor(root.foreground, root.accent)
       : root.active   ? Style.selectedFillFor(root.foreground, root.accent)
       : root.background

  borderSpec: root.activeFocus
              ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
              : Border.controlSpec(
                  root.selected ? "selected" : (root.hot ? "hover-cursor" : "normal"),
                  root.foreground, root.accent)
}
