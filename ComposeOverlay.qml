import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The one surface every capture mode converges on.
//
// It opens only after the screenshot has been taken, so it is never in its own
// shot. Submitting closes it immediately: the model runs detached afterwards,
// and the bar icon reports progress from there.
Item {
  id: root

  property var service: null

  property bool opened: false
  property string memoryId: ""
  property string mode: "screenshot"
  property string imagePath: ""
  property bool hasImage: false
  property bool voiceAvailable: false
  property bool dictating: false

  // A memory with no text, no image and no voice is worthless. The CLI refuses
  // one too, but the button has to say so before the user presses it.
  readonly property bool canSubmit: noteField.text.trim().length > 0 || root.hasImage

  function begin(payload) {
    var data = payload || ({})
    root.memoryId = data.id || ""
    root.mode = data.mode || "screenshot"
    root.imagePath = data.image || ""
    root.hasImage = !!data.hasImage
    // Fails closed, like the bar menu: a capability check should not treat a
    // missing flag as a yes.
    root.voiceAvailable = data.voiceAvailable === true
    noteField.text = ""
    root.opened = true
    Qt.callLater(function () { noteField.forceActiveFocus() })
    if (data.autoDictate && root.voiceAvailable)
      root.dictate()
  }

  function submit() {
    if (!root.canSubmit || !root.memoryId) return
    var args = ["commit", "--id", root.memoryId, "--note", noteField.text]
    if (!root.hasImage) args.push("--remove-image")
    root.opened = false
    // Genuinely detached, not service.call(): enrichment waits on a model for
    // tens of seconds, and a tracked process dies with its QML object -- which
    // a plugin reload destroys, stranding the memory in ai_status='pending'.
    if (service) service.detach(args)
    root.memoryId = ""
  }

  function discard() {
    // memoryId is cleared before the call and on submit, so a dismissal after
    // a commit has nothing to discard. The CLI refuses to delete a saved
    // memory anyway -- belt and braces, because losing one is unrecoverable.
    var id = root.memoryId
    root.opened = false
    root.memoryId = ""
    if (id && service) service.call(["discard", "--id", id], null)
  }

  // Close without discarding. Used when the draft was committed elsewhere, so
  // the overlay is stale rather than cancelled.
  function dismiss() {
    root.opened = false
    root.memoryId = ""
  }

  function dictate() {
    // Voxtype types into the focused window, and the note field is focused, so
    // the transcript lands in it with nothing to intercept.
    root.dictating = true
    Quickshell.execDetached(["voxtype", "record", "toggle"])
  }

  function editImage() {
    if (root.imagePath)
      Quickshell.execDetached(["tensaku-edit", root.imagePath])
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omoide-compose"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.discard() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)
      height: Math.min(content.implicitHeight + Style.spacing.panelPadding * 2,
                       panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                     Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Esc is two-stage: the note field hands focus back here on the first
      // press, and this closes on the second. With the handler only inside the
      // field there was no way to close a focused overlay from the keyboard.
      Item {
        id: overlayKeys
        anchors.fill: parent
        Keys.onPressed: function (event) {
          // A held Escape must discard once, not repeatedly.
          if (event.key === Qt.Key_Escape) {
            if (!event.isAutoRepeat) root.discard()
            event.accepted = true
          }
        }
      }

      Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        // Capture, note field and actions are separate sections of the dialog,
        // so they get a section-sized gap rather than a control-sized one.
        //
        // No heading. The dialog opens on a screenshot with a focused text
        // field: what to do with it is already obvious, and the placeholder
        // says the rest.
        spacing: Style.spacing.xxl

        // The screenshot, at the shape you selected. Removing it turns a
        // screenshot capture into a note-only one. No clip here: it would cut
        // the frame's rounded corners, which the image is already masked to.
        //
        // Bounded by height and never by crop. This was a fixed 2:1 box with
        // PreserveAspectCrop, so a square region came back with its top and
        // bottom cut off; now a square or portrait capture gets narrower
        // instead, and the frame hugs the picture.
        Item {
          id: previewBox
          width: parent.width
          height: root.hasImage
                  ? Math.round(Math.min(Style.space(260), width / previewBox.aspect))
                  : 0
          visible: root.hasImage

          // sourceAspect is 0 until the image loads. 1.6 keeps the box a
          // sensible shape for that one frame rather than collapsing it.
          readonly property real aspect: preview.sourceAspect > 0
                                         ? preview.sourceAspect : 1.6

          RoundedImage {
            id: preview
            x: Math.round((parent.width - width) / 2)
            width: Math.round(Math.min(parent.width,
                                       parent.height * previewBox.aspect))
            height: parent.height
            source: root.imagePath ? "file://" + root.imagePath : ""
            fillMode: Image.PreserveAspectCrop
          }

          // Floating in the frame, inset far enough not to sit on the border.
          //
          // Icons rather than labels: two words were wider than a portrait
          // capture now that the preview keeps its own shape, so they covered
          // the picture they act on.
          //
          // On a backing plate, because these sit over an arbitrary screenshot
          // and a bare glyph disappears against a busy one. Nearly opaque
          // rather than fully, so it reads as floating on the image.
          Rectangle {
            anchors.right: preview.right
            anchors.bottom: preview.bottom
            anchors.rightMargin: Style.spacing.md + preview.borderWidth
            anchors.bottomMargin: Style.spacing.md + preview.borderWidth
            width: imageActions.width + Style.spacing.xs * 2
            height: imageActions.height + Style.spacing.xs * 2
            radius: Style.cornerRadius
            color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                           Color.menu.background.b, 0.88)

            Row {
              id: imageActions
              anchors.centerIn: parent
              spacing: Style.spacing.xxs

              // Nerd Font glyphs, so they need resolvedFamily rather than the
              // menu font -- the same reason ActionMenu's default-action pin
              // does.
              PanelActionButton {
                iconText: "󰏫"
                tooltipText: "Crop or annotate in tensaku"
                size: Style.space(24)
                fontSize: Style.font.body
                foreground: Color.menu.text
                fontFamily: Style.font.resolvedFamily
                onClicked: root.editImage()
              }

              PanelActionButton {
                iconText: "󰩹"
                tooltipText: "Remove the screenshot, keep only the note"
                size: Style.space(24)
                fontSize: Style.font.body
                foreground: Color.menu.text
                // Destructive, so it takes the urgent-tinted hover the
                // component already provides for forget/unpair actions.
                hoverColor: Color.urgent
                fontFamily: Style.font.resolvedFamily
                onClicked: root.hasImage = false
              }
            }
          }
        }

        // The field and its dictate button on one row, anchored rather than
        // spaced so the field always ends where the button begins.
        Item {
          width: parent.width
          height: noteField.height

          AccentField {

            ringBackdrop: Color.menu.background
            id: noteField
            anchors.left: parent.left
            anchors.right: dictateButton.left
            anchors.rightMargin: Style.spacing.controlGap
            anchors.verticalCenter: parent.verticalCenter
            foreground: Color.menu.text
            accent: Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            placeholderText: root.hasImage
                             ? "Optional — add a note, or press Enter to save"
                             : "What do you want to remember?"

            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Escape) {
                // Step out of the input; a second Esc discards the capture.
                if (!event.isAutoRepeat) overlayKeys.forceActiveFocus()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // A held Return would commit the capture more than once.
                if (!event.isAutoRepeat) root.submit()
                event.accepted = true
              }
            }
          }

          // Outlined, and square to the field's own height, so it reads as part
          // of the input rather than as a third action next to Cancel and Save
          // -- which is where it used to sit.
          PanelActionButton {
            id: dictateButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            bordered: true
            size: noteField.height
            iconText: ""
            enabled: root.voiceAvailable
            opacity: root.voiceAvailable ? 1.0 : 0.45
            tooltipText: root.voiceAvailable
                         ? (root.dictating ? "Listening — click to stop"
                                           : "Dictate with Voxtype")
                         : "Voxtype is not installed"
            // Tinted while recording: the button lost its "Listening…" label
            // when it lost its text, so the state has to show some other way.
            foreground: root.dictating ? Color.accent : Color.menu.text
            hoverColor: Color.accent
            fontFamily: Style.font.resolvedFamily
            onClicked: if (root.voiceAvailable) root.dictate()
          }
        }

        Text {
          width: parent.width
          visible: !root.canSubmit
          text: "Add a note or a voice memo to save this."
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        // Anchored, not spaced. A Row plus a fixed-width filler only lines up
        // while the buttons happen to add up to that width -- change a label
        // and Save drifts away from the edge the field is aligned to.
        Item {
          width: parent.width
          height: actionRow.height

          Row {
            id: actionRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            Button {
              text: "Cancel"
              foreground: Color.menu.text
              background: Color.menu.background
              fontFamily: Style.font.menuFamily
              onClicked: root.discard()
            }

            Button {
              text: "Save"
              selected: root.canSubmit
              enabled: root.canSubmit
              opacity: root.canSubmit ? 1.0 : 0.45
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
}
