import QtQuick
import qs.Commons
import qs.Ui
import "../common"

// Correcting what the agent wrote.
//
// Two fields, because a block has at most two editable parts: a heading it
// wrote itself (only lists have one) and its body. Everything else about a
// block -- its type, its position, the items it points at -- is structure, not
// content, and is not editable here.
//
// Saving marks the row `edited`, which is what stops a later retry overwriting
// the correction. That flag is the whole reason this sheet is worth having.
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

  // Escape, on the ROOT so it catches the key wherever focus happens to be.
  //
  // Key events travel up the focused item's PARENT chain. An inner catcher that
  // is a sibling of the content is never on that chain, so once anything else
  // took focus -- a button, a chip, the memory link -- Escape passed the catcher
  // by, reached SpaceWindow, and died there: unwind() steps aside for an open
  // overlay, expecting the overlay to handle its own. The dialog became
  // uncloseable by keyboard.
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

    // Esc closes the dialog. This is the rung the fields blur INTO: they release
    // focus on the first Esc, and the second lands here. Without it the dialog
    // became uncloseable by keyboard once a field had let go, because
    // SpaceWindow's unwind() steps aside for whatever overlay is open.
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

        // The plugin's one multi-line input, shared with the to-do title. It used to
        // be a TextEdit hand-dressed in a BorderSurface here, because the kit has no
        // multi-line field -- which meant this dialog carried its own copy of the
        // accent border, the corner marks and the Escape handoff, and drifted from
        // the fields around it whenever one of those changed.
        AccentTextArea {
          id: bodyEdit
          escapeTo: editorKeys
          width: parent.width
          // Opens at the height the hand-built box had, and stops at twelve lines,
          // which is a full paragraph. Past that it scrolls rather than growing, so
          // a long summary cannot push the dialog's buttons off the bottom.
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
            // focusBorderAlpha (0.25), which reads as grey.
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
            // focusBorderAlpha (0.25), which reads as grey.
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
