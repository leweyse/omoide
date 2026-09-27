import QtQuick
import qs.Commons
import qs.Ui

// A date and a time, as two masked fields. DD/MM/YYYY, which is how the value
// reads locally; the caller converts to what the CLI parses.
//
// The mask fixes the shape, so only digits go in and the caret walks between
// segments.
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
  // Forwarded to both halves, so Esc in the date or the time behaves the
  // same as Esc in any other input.
  property Item escapeTo: null
  property alias dateWidth: dateField.width

  function set(nextDate, nextTime) {
    dateField.text = nextDate || ""
    timeField.text = nextTime || ""
  }

  function focusStart() { dateField.forceActiveFocus() }

  spacing: Style.spacing.controlGap

  AccentField {
    id: dateField
    escapeTo: root.escapeTo
    width: Style.space(118)
    inputMask: "99/99/9999"
    foreground: root.foreground
    accent: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle

    // Caret to the front on entry. With a mask, Qt leaves it wherever the
    // pointer landed or where it last was, so typing would overwrite the middle
    // of the value. callLater because Qt sets the position itself as part of
    // taking focus.
    onActiveFocusChanged: if (activeFocus)
      Qt.callLater(function () { dateField.cursorPosition = 0 })
  }

  AccentField {
    id: timeField
    escapeTo: root.escapeTo
    width: Style.space(74)
    inputMask: "99:99"
    foreground: root.foreground
    accent: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    onActiveFocusChanged: if (activeFocus)
      Qt.callLater(function () { timeField.cursorPosition = 0 })
  }
}
