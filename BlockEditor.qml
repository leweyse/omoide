import QtQuick
import qs.Commons
import qs.Ui

// Correcting what the agent wrote.
//
// Two fields, because a block has at most two editable parts: a heading it
// wrote itself (only lists have one) and its body. Everything else about a
// block -- its type, its position, the items it points at -- is structure, not
// content, and is not editable here.
//
// Saving marks the row `edited`, which is what stops a later retry overwriting
// the correction. That flag is the whole reason this sheet is worth having.
Item {
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
    Qt.callLater(function () { bodyEdit.forceActiveFocus() })
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

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
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

    Column {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.xl

      PanelSectionHeader {
        width: parent.width
        text: root.hasHeading ? "Edit list" : "Edit " + root.blockType
        foreground: Color.menu.text
        fontFamily: Style.font.menuFamily
      }

      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.hasHeading

        Text {
          text: "Heading"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: headingField
          width: parent.width
          foreground: Color.menu.text
          accent: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          placeholderText: "What these items are"
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          text: root.hasHeading ? "One item per line — “Label: text” for a pair"
                                : "Text"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        // A TextEdit inside a BorderSurface rather than a Controls TextArea:
        // the kit has no multi-line input, and this way the frame and the focus
        // state come from the same tokens every other field here uses.
        BorderSurface {
          width: parent.width
          height: Math.max(Style.space(120),
                           bodyEdit.implicitHeight + Style.spacing.inputPaddingY * 2)
          radius: Style.cornerRadius
          color: Style.controlFill(bodyEdit.activeFocus, false,
                                   Color.menu.text, Color.accent)
          borderSpec: Border.controlSpec(bodyEdit.activeFocus ? "focus" : "normal",
                                         Color.menu.text, Color.accent)

          TextEdit {
            id: bodyEdit
            anchors.fill: parent
            anchors.margins: Style.spacing.controlPaddingX
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            color: Color.menu.text
            selectionColor: Style.selectionFillFor(Color.menu.text, Color.accent)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body

            Keys.onEscapePressed: function (event) {
              root.close()
              event.accepted = true
            }
          }
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
            onClicked: root.close()
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
