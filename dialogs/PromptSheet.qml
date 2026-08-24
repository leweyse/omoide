import QtQuick
import qs.Commons
import qs.Ui
import "../common"

// A one-field prompt: a title, a text input, Cancel and Save.
//
// The same shape as ConfirmSheet, which answers a yes/no question. This one
// answers "what should it be called", which a confirmation cannot.
// A FocusScope, not a plain Item.
//
// A scope keeps activeFocus when the child holding it disappears or declines a
// key: focus falls back to the scope instead of vanishing. Without that, a
// focused control being hidden -- a reminder row removed by its own delete
// button -- or a field swallowing Escape left NOTHING focused, and with nothing
// focused no Keys handler in the dialog could fire. The keyboard died and no
// number of Escapes brought it back.
//
// Being the root also puts it on the parent chain of every control inside, so
// the Escape handler below sees keys wherever focus actually sits.
FocusScope {
  id: root

  property bool opened: false
  property string heading: ""
  property string placeholder: ""
  // Whatever the caller needs handed back with the answer.
  property string targetId: ""

  // 0 when this covers a whole screen; the card's inner radius when it
  // is layered inside one.
  property real scrimRadius: 0

  signal accepted(string value, string targetId)
  signal canceled()

  readonly property bool valid: field.text.trim().length > 0

  function open(headingText, initial, id) {
    root.heading = headingText || ""
    root.targetId = id || ""
    field.text = initial || ""
    root.opened = true
    Qt.callLater(function () {
      field.forceActiveFocus()
      field.selectAll()
    })
  }

  function submit() {
    if (!root.valid) return
    var value = field.text.trim()
    var id = root.targetId
    root.opened = false
    root.accepted(value, id)
  }

  visible: opened

  // Escape, on the scope root so it catches the key however deep focus is.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.canceled()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
    // Matches the curve of whatever this is layered over. Anchored inside the
    // Space card, a square scrim paints across the card's rounded corners and
    // the dialog looks like it has square ones.
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.canceled() }
  }

  BorderSurface {
    anchors.centerIn: parent
    width: Math.min(Style.space(380), parent.width - Style.spacing.panelPadding * 2)
    height: layout.implicitHeight + Style.spacing.panelPadding * 2
    radius: Style.cornerRadius
    // Opaque, for the same reason the Space dialog is: a translucent sheet over
    // a page of thumbnails is unreadable.
    color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                   Color.menu.background.b, 1.0)
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                   Math.max(1, Style.space(2)))

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.xl

      PanelSectionHeader {
        width: parent.width
        text: root.heading
        foreground: Color.menu.text
        fontFamily: Style.font.menuFamily
      }

      AccentField {

        ringBackdrop: Color.menu.background
        id: field
        width: parent.width
        foreground: Color.menu.text
        accent: Color.accent
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        placeholderText: root.placeholder
        onAccepted: root.submit()
        Keys.onEscapePressed: function (event) {
          // Only on a real press. Holding Escape auto-repeats, and each repeat
          // would dismiss another layer -- a held key unwound the whole stack.
          if (event.isAutoRepeat) { event.accepted = true; return }
          root.canceled()
          event.accepted = true
        }
      }

      Item {
        width: parent.width
        height: actions.height

        Row {
          id: actions
          anchors.right: parent.right
          spacing: Style.spacing.controlGap

          Button {
            text: "Cancel"
            foreground: Color.menu.text
            background: Color.menu.background
            fontFamily: Style.font.menuFamily
            onClicked: root.canceled()
          }

          Button {
            text: "Save"
            selected: root.valid
            enabled: root.valid
            opacity: root.valid ? 1.0 : 0.45
            foreground: Color.menu.text
            background: Color.menu.background
            accent: Color.accent
            fontFamily: Style.font.menuFamily
            onClicked: root.submit()
          }
        }
      }
    }
  }
}
