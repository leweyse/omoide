import QtQuick
import qs.Commons
import qs.Ui
import "../common"

// A confirmation in the plugin's own dialog language.
//
// Not qs.Ui ConfirmDialog: that one hardcodes a square card and fixed-size
// buttons. Everything here comes from a token (the card's radius, its padding,
// the button chrome), so it matches ItemEditor, SettingsDialog and the compose
// overlay, and follows a theme change with them.
//
// A FocusScope root, so focus falls back to the dialog when the focused child
// disappears or declines a key, and the Escape handler below sees keys from
// every control inside.
FocusScope {
  id: root

  property bool opened: false
  property string message: ""
  property string cancelText: "Cancel"
  property string confirmText: "Confirm"
  property bool destructive: true

  // 0 when this covers a whole screen; the card's inner radius when it
  // is layered inside one.
  property real scrimRadius: 0

  signal canceled()
  signal confirmed()

  function open() {
    root.opened = true
    Qt.callLater(function () { keys.forceActiveFocus() })
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

  Scrim {
    anchors.fill: parent
    // Matches the curve of whatever this is layered over. Anchored inside the
    // Space card, a square scrim paints across the card's rounded corners and
    // the dialog looks like it has square ones.
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.canceled() }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: root.opened

    Keys.onPressed: function (event) {
      // Both ignore auto-repeat. A held Escape would unwind every layer, and a
      // held Return would fire a destructive confirm more than once.
      if (event.key === Qt.Key_Escape) {
        if (!event.isAutoRepeat) root.canceled()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (!event.isAutoRepeat) root.confirmed()
        event.accepted = true
      }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(380), parent.width - Style.spacing.panelPadding * 2)
      height: layout.implicitHeight + Style.spacing.panelPadding * 2
      radius: Style.cornerRadius
      // Opaque, for the same reason the Space dialog is: a translucent sheet
      // over a screenshot is unreadable.
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
        spacing: Style.spacing.xxxl

        Text {
          width: parent.width
          text: root.message
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          lineHeight: 1.25
        }

        // Right-aligned, in an Item rather than a bare Row, so the pair sits
        // flush with the card's padding whatever the labels are.
        Item {
          width: parent.width
          height: actions.height

          Row {
            id: actions
            anchors.right: parent.right
            spacing: Style.spacing.controlGap

            Button {
              text: root.cancelText
              foreground: Color.menu.text
              background: Color.menu.background
              fontFamily: Style.font.menuFamily
              onClicked: root.canceled()
            }

            Button {
              text: root.confirmText
              selected: true
              foreground: root.destructive ? Color.urgent : Color.menu.text
              background: Color.menu.background
              accent: root.destructive ? Color.urgent : Color.accent
              fontFamily: Style.font.menuFamily
              onClicked: root.confirmed()
            }
          }
        }
      }
    }
  }
}
