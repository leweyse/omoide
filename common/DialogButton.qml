import QtQuick
import qs.Commons
import qs.Ui

// A button for the plugin's dialogs, where focus shows in the outline and
// never in the fill.
//
// Two departures from a bare qs.Ui Button:
//
// The fill. Button ranks a focus fill above hover, which spends contrast
// against the label and, on the primary button, replaces the selected fill so
// Save stops looking primary while focused. The border and the ring already
// show focus. Chip.qml follows the same rule.
//
// The border. Border.controlSpec("focus") applies focusBorderAlpha, which makes
// the accent hard to tell from an unfocused control. Border.flat applies none.
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
