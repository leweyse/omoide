import QtQuick
import qs.Commons
import qs.Ui

// A date and a time, as two masked fields. DD/MM/YYYY, which is how the value
// reads locally; the caller converts to what the CLI parses.
//
// The mask is what makes this editable at all: it fixes the shape, so only
// digits go in and the caret walks between segments instead of the user
// retyping a whole phrase to move an appointment by an hour.
//
// Values are read out of the fields rather than bound in both directions. A
// two-way binding between a property and `text` fights itself the moment the
// user types, so initialisation goes through set().
Row {
  id: root

  readonly property string date: dateField.text
  readonly property string time: timeField.text
  readonly property bool complete: dateField.acceptableInput
                                   && timeField.acceptableInput

  property color foreground: Color.menu.text
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property alias dateWidth: dateField.width

  function set(nextDate, nextTime) {
    dateField.text = nextDate || ""
    timeField.text = nextTime || ""
  }

  function focusStart() { dateField.forceActiveFocus() }

  spacing: Style.spacing.controlGap

  TextField {
    id: dateField
    width: Style.space(118)
    inputMask: "99/99/9999"
    foreground: root.foreground
    accent: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.body

    // Caret to the front on entry. With a mask, Qt leaves it wherever the
    // pointer landed or wherever it was last, so typing a fresh date would
    // overwrite the middle of the old one. callLater because Qt sets the
    // position itself as part of taking focus.
    onActiveFocusChanged: if (activeFocus)
      Qt.callLater(function () { dateField.cursorPosition = 0 })
  }

  TextField {
    id: timeField
    width: Style.space(74)
    inputMask: "99:99"
    foreground: root.foreground
    accent: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    onActiveFocusChanged: if (activeFocus)
      Qt.callLater(function () { timeField.cursorPosition = 0 })
  }
}
