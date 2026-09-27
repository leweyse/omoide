import QtQuick
import qs.Commons

// The user's own words, verbatim, and never rewritten by the model.
//
// Labelled rather than decorated: an accent bar down the left edge would read
// as a text cursor and make the card look like a focused input field. "Note" is
// a renderer-owned label, the same as Summary, Event Date and To-dos.
BlockCard {
  id: root
  property var payload: ({})
  property var service: null
  heading: "Note"

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.payload.text || ""
    wrapMode: Text.WordWrap
    color: Color.popups.text
    font.family: Style.font.resolvedFamily
    font.pixelSize: Style.font.subtitle
    lineHeight: 1.25
  }
}
