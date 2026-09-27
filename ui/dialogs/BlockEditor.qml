import QtQuick
import qs.Commons
import qs.Ui
import "../common"

// Correcting what the agent wrote.
//
// Two fields, because a block has at most two editable parts: a heading it
// wrote itself (only lists have one) and its body. Its type, position and the
// items it points at are structure, not content, and are not editable here.
//
// Saving marks the row `edited`, which stops a later retry overwriting the
// correction.
//
// A FocusScope root, so focus falls back to the dialog when the focused child
// disappears or declines a key, and every control inside sits on the parent
// chain the Escape handler below listens on.
FocusScope {
  id: root

  property bool opened: false
  property string blockId: ""
  property string blockType: ""
  // Set for lists, empty for everything else.
  property bool hasHeading: false

  signal saved(string blockId, string heading, string body)

  readonly property bool valid: bodyEdit.text.trim().length > 0

  function open(id, type, heading, body) {
    root.blockId = id
    root.blockType = type
    root.hasHeading = (type === "list")
    headingField.text = heading || ""
    bodyEdit.text = body || ""
    root.opened = true
    // The heading first when the block has one: it sits above the body, so it
    // is the first item in reading order.
    Qt.callLater(function () {
      if (root.hasHeading) headingField.forceActiveFocus()
      else bodyEdit.focusField()
    })
  }

  function close() {
    root.opened = false
    root.blockId = ""
  }

  function submit() {
    if (!root.valid) return
    var id = root.blockId
    var heading = headingField.text.trim()
    var body = bodyEdit.text
    root.close()
    root.saved(id, heading, body)
  }

  visible: opened

  // Escape, on the root, because key events travel up the focused item's
  // parent chain and SpaceWindow's unwind() leaves an open overlay to close
  // itself. A catcher beside the content would miss keys from a focused button.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
  }

  Scrim {
    anchors.fill: parent
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  // 0 when this covers a whole screen; the card's inner radius when it is
  // layered inside one.
  property real scrimRadius: 0

  BorderSurface {
    anchors.centerIn: parent
    width: Math.min(Style.space(520), parent.width - Style.spacing.panelPadding * 2)
    height: layout.implicitHeight + Style.spacing.panelPadding * 2
    radius: Style.cornerRadius
    // Opaque, for the same reason the Space dialog is: a translucent sheet over
    // a page of thumbnails is unreadable.
    color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                   Color.menu.background.b, 1.0)
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                   Math.max(1, Style.space(2)))

    MouseArea { anchors.fill: parent; onClicked: {} }

    // Esc closes the dialog. The fields release focus on the first Esc and
    // blur into this item, so the second Esc lands here.
    Item {
      id: editorKeys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
      }
    }

    Column {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.xxl

      PanelSectionHeader {
        width: parent.width
        text: root.hasHeading ? "Edit list" : "Edit " + root.blockType
        foreground: Color.menu.text
        fontFamily: Style.font.menuFamily
      }

      Column {
        width: parent.width
        spacing: Style.spacing.lg
        visible: root.hasHeading

        Text {
          text: "Heading"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        AccentField {
          id: headingField
          escapeTo: editorKeys
          width: parent.width
          foreground: Color.menu.text
          accent: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          placeholderText: "What these items are"
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.lg

        Text {
          text: root.hasHeading ? "One item per line — “Label: text” for a pair"
                                : "Text"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        // The plugin's one multi-line input, shared with the to-do title, so the
        // accent border, the corner marks and the Escape handoff match the
        // fields around it.
        AccentTextArea {
          id: bodyEdit
          escapeTo: editorKeys
          width: parent.width
          // Past maxLines it scrolls rather than growing, so a long summary
          // cannot push the dialog's buttons off the bottom.
          minLines: 6
          maxLines: 12
          selectByMouse: true
          foreground: Color.menu.text
          accent: Color.accent
          ringBackdrop: Color.menu.background
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
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
            focusable: true
            FocusRing {
              diagonalCorners: true
              anchors.fill: parent
              radius: parent.radius
              gap: 1
              hasCursor: parent.activeFocus
  backdrop: Color.menu.background
              hot: false
            }
            // Full-strength accent on focus: controlSpec("focus") applies
            // focusBorderAlpha, which reads as grey.
            borderSpec: activeFocus
                        ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                        : Border.controlSpec(
                            selected ? "selected" : (hot ? "hover-cursor" : "normal"),
                            foreground, accent)
            text: "Cancel"
            foreground: Color.menu.text
            background: Color.menu.background
            fontFamily: Style.font.menuFamily
            onClicked: root.close()
          }

          Button {
            focusable: true
            FocusRing {
              diagonalCorners: true
              anchors.fill: parent
              radius: parent.radius
              gap: 1
              hasCursor: parent.activeFocus
  backdrop: Color.menu.background
              hot: false
            }
            // Full-strength accent on focus: controlSpec("focus") applies
            // focusBorderAlpha, which reads as grey.
            borderSpec: activeFocus
                        ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                        : Border.controlSpec(
                            selected ? "selected" : (hot ? "hover-cursor" : "normal"),
                            foreground, accent)
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
