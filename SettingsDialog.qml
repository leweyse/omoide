import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Choosing the model that enriches captures.
//
// A dialog in the plugin, not gum in a terminal. The terminal route opened a
// window with nothing in it -- xdg-terminal-exec's -e took only the binary and
// dropped the subcommand -- and a themed surface is what the rest of the
// plugin already is.
//
// Its own surface, owned by the service rather than the Space dialog: choosing
// a model has nothing to do with browsing memories, and hosting it inside
// Space meant both had to open at once.
// A FocusScope, not a plain Item.
//
// A scope keeps activeFocus when the child holding it disappears or declines a
// key: focus falls back to the scope instead of vanishing. Without that, a
// focused control being hidden or a field swallowing Escape left NOTHING
// focused, and with nothing focused no Keys handler in the dialog could fire.
//
// Being the root also puts it on the parent chain of every control inside, so
// the Escape handler sees keys wherever focus actually sits.
FocusScope {
  id: root

  property var service: null
  property bool opened: false

  // Escape, on the scope root so it catches the key however deep focus is.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
  }
  property var config: ({ providers: [], visionMode: "ocr", enabled: false })

  property string chosen: ""
  property string customCommand: ""
  property string model: ""
  property string vision: "ocr"

  signal saved()

  readonly property var providers: (config && config.providers) || []

  // Presets plus custom, as one list: custom used to be a separate row below
  // the repeater, which cannot participate in a grid layout.
  readonly property var choices: {
    var out = []
    for (var i = 0; i < root.providers.length; i++) out.push(root.providers[i])
    out.push({
      id: "custom",
      command: "reads a prompt on stdin, prints JSON",
      available: true,
      vision: false,
      needsModel: false
    })
    return out
  }
  readonly property bool isCustom: root.chosen === "custom"
  readonly property var chosenProvider: {
    for (var i = 0; i < root.providers.length; i++)
      if (root.providers[i].id === root.chosen) return root.providers[i]
    return null
  }
  // Whether `image` is offerable at all. A custom command is its own case:
  // the CLI hands it the image path when visionMode is "image" (run_ai in
  // bin/omoide), so it must be selectable -- but we cannot claim on
  // the user's behalf that their command reads images, so it carries no
  // "reads images" marker.
  readonly property bool visionCapable: root.isCustom
    || !!(root.chosenProvider && root.chosenProvider.vision)
  onVisionCapableChanged: if (!root.visionCapable) root.vision = "ocr"

  readonly property bool canSave: root.isCustom
    ? root.customCommand.trim().length > 0
    : (!!root.chosenProvider && root.chosenProvider.available
       && (!root.chosenProvider.needsModel || root.model.trim().length > 0))

  function open() {
    if (!service) return
    service.call(["ai-config"], function (code, json) {
      if (!json) return
      root.config = json
      root.chosen = (json.command && json.command.length) ? "custom" : (json.provider || "")
      root.customCommand = (json.command || []).join(" ")
      root.model = json.model || ""
      root.vision = json.visionMode || "ocr"
      root.opened = true
      Qt.callLater(function () { keys.forceActiveFocus() })
    })
  }

  function close() { root.opened = false }

  function save() {
    if (!service || !root.canSave) return
    var args = ["setup-ai", "--vision",
                root.visionCapable ? root.vision : "ocr"]
    if (root.isCustom) {
      args = args.concat(["--provider", "custom", "--command", root.customCommand.trim()])
    } else {
      args = args.concat(["--provider", root.chosen])
      if (root.model.trim().length) args = args.concat(["--model", root.model.trim()])
    }
    service.call(args, function () {
      root.saved()
      root.close()
    })
  }

  function disable() {
    if (!service) return
    service.call(["setup-ai", "--disable"], function () {
      root.saved()
      root.close()
    })
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omoide-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: sheet
      anchors.centerIn: parent
      width: Math.min(Style.space(620), parent.width - Style.gapsOut * 2)
      height: Math.min(layout.implicitHeight + Style.spacing.panelPadding * 2,
                       parent.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                     Color.menu.background.b, 1.0)
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                     Math.max(1, Style.space(2)))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
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

        Column {
          id: layout
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.xxl

          Item {
            width: parent.width
            height: Math.max(sheetTitle.implicitHeight, turnOff.height)

            Text {
              id: sheetTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Agent for Omoide"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.subtitle
            }

            // Turning enrichment off is a rare, destructive-ish action, so it
            // sits out of the way of Cancel / Use this model rather than
            // beside them where it can be hit by accident. The tooltip carries
            // what the button no longer says in words.
            PanelActionButton {
              id: turnOff
              anchors.right: parent.right
              anchors.verticalCenter: sheetTitle.verticalCenter
              visible: root.config.enabled === true
              iconText: "⏻"
              tooltipText: "Turn enrichment off. Captures still save — note, "
                         + "screenshot, and any date read without an agent."
              size: Style.space(26)
              fontSize: Style.font.body
              foreground: Color.menu.text
              fontFamily: Style.font.menuFamily
              onClicked: root.disable()
            }
          }

          Text {
            width: parent.width
            text: "Enrichment runs the agent you pick here — the same CLI you "
                  + "already use, invoked once per capture. Nothing runs until "
                  + "you choose one, and a capture still saves without it: its "
                  + "note, its screenshot, and any date it can read on its own."
            wrapMode: Text.WordWrap
            color: Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          // One row per preset, plus custom. An uninstalled provider is shown
          // disabled with the reason rather than hidden.
          // Two columns. Seven choices at a comfortable gap do not fit the
          // dialog in one column, and shrinking the gap to make them fit is
          // what made the list hard to scan in the first place.
          Grid {
            id: providerGrid
            width: parent.width
            columns: 2
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.md
            readonly property real cellWidth: (width - columnSpacing) / columns

            Repeater {
              model: root.choices

              delegate: ChoiceCard {
                required property var modelData

                width: providerGrid.cellWidth
                title: modelData.id + (modelData.vision ? "   · reads images" : "")
                detail: modelData.available
                        ? modelData.command
                        : modelData.id + " is not installed"
                picked: root.chosen === modelData.id
                selectable: modelData.available
                onChose: root.chosen = modelData.id
              }
            }
          }

          AccentField {

            ringBackdrop: Color.menu.background
            width: parent.width
            visible: root.isCustom
            text: root.customCommand
            foreground: Color.menu.text
            accent: Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            placeholderText: "my-agent --json"
            onTextChanged: root.customCommand = text
            Keys.onEscapePressed: function (event) {
              // Only on a real press. Holding Escape auto-repeats, and each repeat
              // would dismiss another layer -- a held key unwound the whole stack.
              if (event.isAutoRepeat) { event.accepted = true; return }
              keys.forceActiveFocus()
              event.accepted = true
            }
          }

          AccentField {

            ringBackdrop: Color.menu.background
            width: parent.width
            visible: !!(root.chosenProvider && root.chosenProvider.needsModel)
            text: root.model
            foreground: Color.menu.text
            accent: Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            placeholderText: "model to run, e.g. llama3.2"
            onTextChanged: root.model = text
            Keys.onEscapePressed: function (event) {
              // Only on a real press. Holding Escape auto-repeats, and each repeat
              // would dismiss another layer -- a held key unwound the whole stack.
              if (event.isAutoRepeat) { event.accepted = true; return }
              keys.forceActiveFocus()
              event.accepted = true
            }
          }

          PanelSeparator { width: parent.width; foreground: Color.menu.text }

          Column {
            width: parent.width
            spacing: Style.spacing.md

            Text {
              text: "What the agent sees from a screenshot"
              color: Color.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            // The same cards as the agent grid above, in the same two columns.
            // This was a two-segment toggle with its description underneath,
            // which meant the description only ever described the mode you had
            // already picked -- you had to select the other one to find out
            // what it did. As cards both trade-offs are on screen at once, and
            // `image` carries its own reason when the chosen agent cannot use
            // it, exactly as an uninstalled agent does.
            Grid {
              id: visionGrid
              width: parent.width
              columns: 2
              columnSpacing: Style.spacing.md
              rowSpacing: Style.spacing.md
              readonly property real cellWidth: (width - columnSpacing) / columns

              ChoiceCard {
                width: visionGrid.cellWidth
                title: "ocr"
                detail: "Text pulled out with tesseract. Works with any agent, "
                        + "and the screenshot never leaves this machine."
                picked: root.vision === "ocr"
                onChose: root.vision = "ocr"
              }

              ChoiceCard {
                width: visionGrid.cellWidth
                title: "image"
                detail: root.isCustom
                        ? "The screenshot's path, for a command that can open it."
                        : (root.visionCapable
                           ? "The screenshot itself. Better on charts and on "
                             + "dense pages, where flattened text loses the layout."
                           : (root.chosen === ""
                              ? "Needs an agent that reads images."
                              : root.chosen + " does not read images."))
                picked: root.vision === "image"
                selectable: root.visionCapable
                onChose: root.vision = "image"
              }
            }
          }

          Item {
            width: parent.width
            height: settingsActions.height

            Row {
              id: settingsActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
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
                selected: root.canSave
                enabled: root.canSave
                opacity: root.canSave ? 1.0 : 0.45
                foreground: Color.menu.text
                background: Color.menu.background
                accent: Color.accent
                fontFamily: Style.font.menuFamily
                onClicked: root.save()
              }
            }
          }
        }
      }
    }
  }
}
