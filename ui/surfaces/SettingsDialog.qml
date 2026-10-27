import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../common"
import "../components"

// Choosing the agent that enriches captures, what it sees, and what else it
// may use.
//
// Its own surface, owned by the service rather than the Space dialog, so it
// opens without Space.
//
// The root is a FocusScope, so focus falls back to it when the focused child
// disappears or declines a key. With nothing focused, no Keys handler here
// would fire. Being the root also puts it on the parent chain of every
// control, so the Escape handler sees keys wherever focus sits.
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
  property var config: ({ providers: [], visionMode: "ocr", allowTools: [], enabled: false })

  property string chosen: ""
  property string customCommand: ""
  property string model: ""
  property string vision: "ocr"
  // What the agent may use: "web_search" and "mcp:<server>" entries.
  property var allow: []
  // Each agent's MCP servers, by agent id: a list once listed, "loading" while
  // `ai-servers` runs, "failed" when it could not list them.
  property var servers: ({})
  // The command and restriction for the current choices, from `ai-preview`,
  // and the arguments it was last asked with: only that answer is kept.
  property var preview: null
  property string previewKey: ""
  property bool showCommand: false
  // Which tool the arrow keys are on, in the Tools section.
  property int toolCursor: 0
  // Which section the arrow keys change: 0 agent, 1 screenshot, 2 tools.
  property int section: 0

  // Room between the four sections, and between the scrolling body and the
  // header and footer it sits between. Inside a section, things sit
  // Style.spacing.xl apart.
  readonly property real sectionGap: Style.space(28)
  readonly property real bodyGap: Style.space(22)

  signal saved()

  readonly property var providers: (config && config.providers) || []

  // What the "What runs" line shows for a custom command, which no preview
  // describes: it runs as typed.
  readonly property var customChoice: ({
    id: "custom",
    command: root.customCommand.trim() || "your command, run with sh -c",
    restriction: "run as written, so add your agent's own read-only flag"
  })

  // Installed presets plus custom take a segment each; an uninstalled one is
  // named in the caption instead.
  readonly property var choices: {
    var out = []
    for (var i = 0; i < root.providers.length; i++)
      if (root.providers[i].available) out.push(root.providers[i])
    out.push(root.customChoice)
    return out
  }
  readonly property var missing: {
    var out = []
    for (var i = 0; i < root.providers.length; i++)
      if (!root.providers[i].available) out.push(root.providers[i].id)
    return out
  }
  readonly property bool isCustom: root.chosen === "custom"
  readonly property var chosenProvider: {
    for (var i = 0; i < root.providers.length; i++)
      if (root.providers[i].id === root.chosen) return root.providers[i]
    return null
  }
  // Whether `image` is offerable at all. A custom command gets the image path
  // when visionMode is "image" (run_ai in cli/src/enrich.c), so it is
  // selectable. Nothing here knows whether the user's command reads images.
  readonly property bool visionCapable: root.isCustom
    || !!(root.chosenProvider && root.chosenProvider.vision)
  onVisionCapableChanged: if (!root.visionCapable) root.vision = "ocr"

  // The command and restriction the "What runs" line shows. A preset's come
  // from `ai-preview`, which builds them with harden(), so the line cannot
  // drift from what runs.
  readonly property var running: root.isCustom ? root.customChoice : root.preview

  // The tools on offer for the chosen agent: web search, then its servers.
  readonly property bool listsServers: !!(root.chosenProvider && root.chosenProvider.listsServers)
  readonly property var serverState: root.servers[root.chosen]
  readonly property var toolChoices: {
    if (!root.listsServers) return []
    var out = [{ value: "web_search", label: "web search" }]
    if (Array.isArray(root.serverState))
      for (var i = 0; i < root.serverState.length; i++)
        out.push({ value: "mcp:" + root.serverState[i], label: root.serverState[i] })
    return out
  }

  function allows(value) { return root.allow.indexOf(value) >= 0 }

  function toggle(value) {
    var next = root.allow.slice()
    var at = next.indexOf(value)
    if (at >= 0) next.splice(at, 1)
    else next.push(value)
    root.allow = next
  }

  // Lists the agent's servers again, after a change to its own config. The
  // list is otherwise kept across opens, since claude's listing takes seconds.
  function refreshServers() {
    if (!root.listsServers || root.serverState === "loading") return
    var next = Object.assign({}, root.servers)
    delete next[root.chosen]
    root.servers = next
    root.loadServers()
  }

  // Lists the chosen agent's servers once, then drops any allowed
  // server missing from that list, so a save never keeps a name that loads
  // nothing.
  function loadServers() {
    var agent = root.chosen
    if (!service || !root.listsServers || root.servers[agent] !== undefined) {
      root.pruneAllow()
      return
    }
    var marked = Object.assign({}, root.servers)
    marked[agent] = "loading"
    root.servers = marked
    service.call(["ai-servers", "--provider", agent], function (code, json) {
      var next = Object.assign({}, root.servers)
      next[agent] = (code === 0 && json && Array.isArray(json.servers)) ? json.servers : "failed"
      root.servers = next
      if (root.chosen === agent) root.pruneAllow()
    })
  }

  function pruneAllow() {
    var known = root.toolChoices.map(function (t) { return t.value })
    var settled = Array.isArray(root.serverState)
    var kept = root.allow.filter(function (v) {
      return v === "web_search" ? root.listsServers : (!settled || known.indexOf(v) >= 0)
    })
    // Reassigning an equal list would still re-run the preview.
    if (kept.length !== root.allow.length) root.allow = kept
    root.toolCursor = Math.min(root.toolCursor, Math.max(0, root.toolChoices.length - 1))
  }

  // Several choices can change in one turn; preview them once.
  function refreshPreview() { Qt.callLater(root.runPreview) }

  function runPreview() {
    if (!service || root.isCustom || !root.chosenProvider) { root.preview = null; return }
    var args = ["ai-preview", "--provider", root.chosen, "--vision", root.vision]
    for (var i = 0; i < root.allow.length; i++) args = args.concat(["--allow", root.allow[i]])
    var asked = args.join("\u0000")
    service.call(args, function (code, json) {
      if (asked !== root.previewKey) return
      root.preview = (code === 0 && json) ? json : null
    })
    root.previewKey = asked
  }

  // Only once open: open() sets all three, then lists and previews once.
  // Listing waits for the choice to settle, because arrowing across the
  // agents would otherwise run each one's listing, and claude's starts every
  // server it checks.
  onChosenChanged: if (root.opened) { listSoon.restart(); root.refreshPreview() }

  Timer {
    id: listSoon
    interval: 300
    onTriggered: root.loadServers()
  }
  onVisionChanged: if (root.opened) root.refreshPreview()
  onAllowChanged: if (root.opened) root.refreshPreview()

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
      root.allow = json.allowTools || []
      root.toolCursor = 0
      root.showCommand = false
      root.section = 0
      body.contentY = 0
      root.opened = true
      root.loadServers()
      root.refreshPreview()
      Qt.callLater(function () { keys.forceActiveFocus() })
    })
  }

  function close() { root.opened = false }

  function save() {
    if (!service || !root.canSave) return
    var args = ["setup-ai", "--vision",
                root.visionCapable ? root.vision : "ocr"]
    // An empty --allow says "none", so a save always states the whole list.
    var allowed = root.isCustom ? [] : root.allow
    args = args.concat(["--allow", ""])
    for (var i = 0; i < allowed.length; i++) args = args.concat(["--allow", allowed[i]])
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

  // Scrolls the body just enough to show `item`, keeping the panel padding at
  // the edge, the way the library views bring their keyboard cursor on screen.
  function reveal(item) {
    if (!item || !item.visible) return
    var top = item.mapToItem(layout, 0, 0).y
    var bottom = top + item.height
    var pad = Style.spacing.panelPadding
    var limit = Math.max(0, body.contentHeight - body.height)
    if (top - pad < body.contentY)
      body.contentY = Math.max(0, top - pad)
    else if (bottom + pad > body.contentY + body.height)
      body.contentY = Math.min(limit, bottom + pad - body.height)
  }

  // Arrow keys within the focused section. Every section is one row of
  // choices, so any arrow moves one step.
  function step(delta) {
    if (root.section === 0) {
      var at = -1
      for (var i = 0; i < root.choices.length; i++)
        if (root.choices[i].id === root.chosen) at = i
      var next = at < 0 ? 0 : at + delta
      if (next >= 0 && next < root.choices.length) root.chosen = root.choices[next].id
    } else if (root.section === 1) {
      if (root.visionCapable) root.vision = root.vision === "ocr" ? "image" : "ocr"
    } else if (root.toolChoices.length) {
      root.toolCursor = Math.max(0, Math.min(root.toolChoices.length - 1, root.toolCursor + delta))
    }
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

    Scrim { anchors.fill: parent }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: sheet
      anchors.centerIn: parent
      width: Math.min(Style.space(760), parent.width - Style.gapsOut * 2)
      // The header and the actions always show; the body between them scrolls
      // when the screen is too short for all of it.
      height: Math.min(header.implicitHeight + layout.implicitHeight + footer.height
                         + root.bodyGap * 2 + Style.spacing.panelPadding * 2,
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
          } else if (event.key === Qt.Key_Tab) {
            root.section = (root.section + 1) % 3
          } else if (event.key === Qt.Key_Backtab) {
            root.section = (root.section + 2) % 3
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.step(-1)
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root.step(1)
          } else if (event.key === Qt.Key_Space) {
            if (root.section === 2 && root.toolChoices.length)
              root.toggle(root.toolChoices[root.toolCursor].value)
          } else if (event.key === Qt.Key_R) {
            root.refreshServers()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.save()
          } else {
            return
          }
          event.accepted = true
        }

        Column {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.lg

          Item {
            width: parent.width
            height: Math.max(sheetTitle.implicitHeight, turnOff.height)

            Text {
              id: sheetTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Settings"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
            }

            // Turning enrichment off is rare and loses the choice, so it sits
            // away from Cancel and Save. The tooltip says what the icon does.
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
            text: "Enrichment runs your agent once per capture, with its shell "
                  + "off and in an empty directory. Captures save without it."
            wrapMode: Text.WordWrap
            color: Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }

        // Full width, with the panel padding inside it as the library views
        // keep theirs, so the clip edge is never flush with a control's border.
        // At a fractional scale that edge falls between device pixels and takes
        // a flush border's outer line with it.
        Flickable {
          id: body
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: header.bottom
          anchors.topMargin: root.bodyGap
          anchors.bottom: footer.top
          anchors.bottomMargin: root.bodyGap
          contentHeight: layout.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          PageWheel { page: body }

          Column {
            id: layout
            x: Style.spacing.panelPadding
            width: body.width - Style.spacing.panelPadding * 2
            spacing: root.sectionGap

            // --- agent

            Column {
              width: parent.width
              spacing: Style.spacing.xl

              OptionRow {
                width: parent.width
                label: "Agent"
                active: root.section === 0
                options: root.choices.map(function (c) {
                  return { value: c.id, label: c.id, enabled: true }
                })
                value: root.chosen
                onPicked: function (value) { root.chosen = value; root.section = 0 }
                caption: {
                  var what = root.isCustom ? "Reads a prompt on stdin and prints JSON."
                             : (root.chosenProvider
                                ? (root.chosenProvider.vision ? "Reads images." : "Reads text only.")
                                : "Pick the agent that enriches captures.")
                  return root.missing.length
                         ? what + " Not installed: " + root.missing.join(", ") + "."
                         : what
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
                font.pixelSize: Style.font.subtitle
                placeholderText: "my-agent --json"
                onTextChanged: root.customCommand = text
                Keys.onEscapePressed: function (event) {
                  // Only on a real press. Holding Escape auto-repeats, and each
                  // repeat would dismiss another layer.
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
                font.pixelSize: Style.font.subtitle
                placeholderText: "model to run, e.g. llama3.2"
                onTextChanged: root.model = text
                Keys.onEscapePressed: function (event) {
                  // Only on a real press. Holding Escape auto-repeats, and each
                  // repeat would dismiss another layer.
                  if (event.isAutoRepeat) { event.accepted = true; return }
                  keys.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            // --- screenshot

            OptionRow {
              width: parent.width
              label: "Screenshot"
              active: root.section === 1
              options: [
                { value: "ocr", label: "ocr", enabled: true },
                { value: "image", label: "image", enabled: root.visionCapable }
              ]
              value: root.vision
              onPicked: function (value) { root.vision = value; root.section = 1 }
              caption: root.vision === "image"
                       ? (root.isCustom
                          ? "Your command gets the screenshot's path."
                          : "The screenshot itself. Better on charts and dense "
                            + "pages, where flattened text loses the layout.")
                       : "Text read with tesseract. The screenshot never "
                         + "leaves this machine."
                         + (root.visionCapable || root.chosen === "" ? ""
                            : " " + root.chosen + " does not read images.")
            }

            // --- tools

            // Nothing is allowed until ticked here. Built-in tools are known up
            // front; servers come from the agent's own listing, so they load.
            Column {
              id: toolsSection
              width: parent.width
              spacing: Style.spacing.xl

              readonly property real rowLabelWidth: Style.space(96)
              readonly property real chipHeight: Math.ceil(chipMetrics.height) + Style.spacing.controlPaddingY * 2

              FontMetrics {
                id: chipMetrics
                font.family: Style.font.resolvedFamily
                font.pixelSize: Style.font.body
              }

              Text {
                text: "Tools"
                color: root.section === 2 ? Color.accent : Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.capitalization: Font.AllUppercase
              }

              Repeater {
                // Web search is toolChoices[0]; the servers follow it, so a
                // row's chips keep their index into toolChoices for the cursor.
                model: root.listsServers ? [
                  { label: "Built in", first: 0, count: 1, loading: false, empty: "" },
                  { label: "MCP servers", first: 1, count: root.toolChoices.length - 1,
                    loading: root.serverState === "loading",
                    empty: root.serverState === "failed" ? "could not list them"
                                                         : "none configured" }
                ] : []

                delegate: Row {
                  id: toolRow
                  required property var modelData
                  width: toolsSection.width

                  Text {
                    width: toolsSection.rowLabelWidth
                    height: toolsSection.chipHeight
                    verticalAlignment: Text.AlignVCenter
                    text: toolRow.modelData.label
                    color: Color.muted
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                  }

                  Flow {
                    width: toolRow.width - toolsSection.rowLabelWidth
                    spacing: Style.spacing.lg

                    Repeater {
                      model: root.toolChoices.slice(toolRow.modelData.first,
                                                    toolRow.modelData.first + toolRow.modelData.count)

                      delegate: Chip {
                        required property var modelData
                        required property int index
                        readonly property int at: toolRow.modelData.first + index
                        readonly property bool on: root.allows(modelData.value)

                        // Font Awesome's checked and empty square, from the
                        // icon font the menu's glyphs use: "☑" falls back to a
                        // colour emoji.
                        glyph: on ? "\uf046" : "\uf096"
                        label: modelData.label
                        outlined: !on
                        tint: on ? Color.accent : Color.menu.text
                        interactive: true
                        hasCursor: root.section === 2 && root.toolCursor === at
                        onHasCursorChanged: if (hasCursor) root.reveal(this)
                        onClicked: {
                          root.section = 2
                          root.toolCursor = at
                          root.toggle(modelData.value)
                        }
                      }
                    }

                    // Placeholders at a chip's height, in a few widths so they
                    // do not read as real names.
                    Repeater {
                      model: toolRow.modelData.loading ? [0.9, 1.3, 1.1] : []

                      delegate: Skeleton {
                        required property real modelData
                        width: Math.round(Style.space(96) * modelData)
                        height: toolsSection.chipHeight
                      }
                    }

                    Text {
                      visible: !toolRow.modelData.loading && toolRow.modelData.count === 0
                      height: toolsSection.chipHeight
                      verticalAlignment: Text.AlignVCenter
                      text: toolRow.modelData.empty
                      color: Color.muted
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.body
                    }

                    // The list is kept across opens; this reads it again.
                    Chip {
                      visible: toolRow.modelData.first > 0 && !toolRow.modelData.loading
                      glyph: "\uf021"
                      label: "relist"
                      outlined: true
                      tint: Color.muted
                      interactive: true
                      onClicked: root.refreshServers()
                    }
                  }
                }
              }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                text: {
                  if (root.isCustom)
                    return "A custom command runs as you wrote it, so this does not apply."
                  if (!root.listsServers)
                    return root.chosen === "" ? "Pick an agent to see its tools."
                                              : root.chosen + " runs as a plain model, with no tools."
                  return root.allow.length
                         ? "Servers come from " + root.chosen + "'s own config."
                         : "Nothing allowed: the agent reads only the capture."
                }
              }

              Text {
                width: parent.width
                visible: !root.isCustom && root.allow.length > 0
                text: "⚠ Text on a captured screen can steer what you allow, and "
                      + "what it reads reaches the model."
                wrapMode: Text.WordWrap
                color: Color.urgent
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }
            }

            // --- what runs

            Column {
              width: parent.width
              spacing: Style.spacing.xl
              visible: root.running !== null

              PanelSeparator { width: parent.width; foreground: Color.menu.text }

              Item {
                width: parent.width
                height: runsLabel.implicitHeight

                Text {
                  id: runsLabel
                  text: (root.showCommand ? "▾ " : "▸ ") + "What runs"
                  color: Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.subtitle
                }

                MouseArea {
                  anchors.fill: runsLabel
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCommand = !root.showCommand
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.running ? root.running.restriction : ""
                wrapMode: Text.WordWrap
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                visible: root.showCommand
                textFormat: Text.PlainText
                text: root.running ? root.running.command : ""
                wrapMode: Text.WrapAnywhere
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Item {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.panelPadding
          height: settingsActions.height

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Tab section · arrows choose · Space allow · R relist · Enter save"
            color: Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

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
