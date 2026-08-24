import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../components"

// The right-click menu: the capture modes, plus the two destinations.
//
// An unavailable action is shown disabled with the reason rather than hidden,
// so "why can't I record a voice note" has an answer on screen.
Item {
  id: root

  property QtObject bar: null
  property Item anchorItem: null
  property var service: null
  property string defaultAction: "screenshot"

  signal defaultRequested(string action)

  // One inset for both axes of a row. They were rowPaddingX (12) across and
  // sm (4) down, so the highlight was padded three times wider than it was tall.
  readonly property real rowInset: Style.spacing.lg

  readonly property bool opened: panel.open
  // Fails closed. `!== false` treated a missing flag as available, which is the
  // wrong default for a capability check: better to hide an action that would
  // have worked than to offer one that cannot.
  readonly property bool voiceAvailable: !!(service && service.index
                                            && service.index.voiceAvailable === true)
  property int cursor: 0

  readonly property int memoryCount: (service && service.index
                                      && service.index.memoryCount) || 0
  readonly property int enriching: service ? service.enrichingCount : 0
  readonly property int failed: service ? service.failedCount : 0
  readonly property int todos: service ? service.openTodoCount : 0

  // Same precedence as the bar icon: what is happening now outranks what is
  // stored, so the panel and the bar never disagree.
  readonly property string iconMode: root.enriching > 0 ? "working"
                                   : (root.failed > 0 ? "failed" : "idle")

  readonly property string statusLine: {
    if (root.enriching > 0)
      return root.enriching + (root.enriching === 1 ? " capture enriching"
                                                    : " captures enriching")
    if (root.failed > 0)
      return root.failed + (root.failed === 1 ? " capture needs a look"
                                              : " captures need a look")
    if (root.memoryCount === 0) return "Nothing captured yet"
    var line = root.memoryCount + (root.memoryCount === 1 ? " memory" : " memories")
    if (root.todos > 0)
      line += "  ·  " + root.todos + (root.todos === 1 ? " to-do" : " to-dos")
    return line
  }

  function open() {
    root.cursor = 0
    panel.open = true
    if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
  }

  function close() {
    panel.open = false
    if (bar && typeof bar.releasePopout === "function") bar.releasePopout(root)
  }

  function closeForPopoutSwitch() { panel.open = false }

  readonly property var entries: [
    { id: "screenshot", glyph: "", label: "Screenshot", kind: "capture" },
    { id: "note", glyph: "", label: "Quick note", kind: "capture" },
    { id: "voice", glyph: "", label: "Voice note", kind: "capture",
      enabled: root.voiceAvailable, reason: "Needs Voxtype dictation" },
    { id: "clipboard", glyph: "", label: "From clipboard", kind: "capture",
      enabled: false, reason: "Not available yet" },
    { id: "separator", kind: "separator" },
    { id: "space", glyph: "", label: "Open library", kind: "action" },
    { id: "settings", glyph: "", label: "Choose an agent…", kind: "action" }
  ]

  function activate(entry) {
    if (!entry || entry.kind === "separator") return
    if (entry.enabled === false) return
    root.close()
    if (!service) return
    if (entry.kind === "capture") {
      service.capture(entry.id)
    } else if (entry.id === "space") {
      service.showSpace({})
    } else if (entry.id === "settings") {
      // An in-plugin dialog, not gum in a terminal: xdg-terminal-exec's -e
      // took only the binary and dropped the subcommand, so the terminal
      // opened with nothing to fill in.
      service.showSettings()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: false
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(270))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function (dx, dy) {
        var next = root.cursor
        do {
          next = (next + dy + root.entries.length) % root.entries.length
        } while (root.entries[next].kind === "separator")
        root.cursor = next
      }
      // PanelKeyCatcher emits BOTH returnRequested and activateRequested for
      // Enter, so handling both ran the action twice. For a screenshot that
      // was fatal: omarchy-capture-screenshot starts with `pkill slurp &&
      // exit 0`, so the second invocation cancelled the first one's picker.
      onActivateRequested: root.activate(root.entries[root.cursor])

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(2)

        // Every other plugin panel opens with one of these, and without it the
        // menu read as a bare list with no idea whose it was. The icon is the
        // bar mark itself, in whatever state it is currently in.
        PanelHero {
          width: parent.width
          title: "Omoide"
          meta: root.statusLine
          foreground: Color.popups.text
          fontFamily: Style.font.resolvedFamily
          iconComponent: Component {
            SpaceIcon {
              iconSize: Style.font.display
              color: Color.popups.text
              accentColor: Color.accent
              urgentColor: Color.urgent
              mode: root.iconMode
            }
          }
        }

        Item { width: 1; height: Style.spacing.sm }

        PanelSeparator {
          width: parent.width
          foreground: Color.popups.text
        }

        Item { width: 1; height: Style.spacing.sm }

        Repeater {
          model: root.entries

          delegate: Loader {
            required property var modelData
            required property int index
            width: column.width
            sourceComponent: modelData.kind === "separator" ? separatorRow : entryRow

            Component {
              id: separatorRow
              Item {
                height: Style.space(9)
                PanelSeparator {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  foreground: Color.popups.text
                }
              }
            }

            Component {
              id: entryRow
              CursorSurface {
                readonly property bool disabled: modelData.enabled === false
                // Rows with a reason line are two lines tall; popupRowHeight
                // is a single-line metric and cramped them.
                height: entryText.implicitHeight + root.rowInset * 2
                radius: Style.space(5)
                hasCursor: root.cursor === index
                bordered: false
                foreground: Color.popups.text
                opacity: disabled ? 0.45 : 1.0

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: parent.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onEntered: root.cursor = index
                  onClicked: root.activate(modelData)
                }

                // Sets the quick action rather than running it, so the
                // left-click default is changeable from the same place the
                // modes are listed.
                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: root.rowInset
                  anchors.verticalCenter: parent.verticalCenter
                  z: 2
                  visible: modelData.kind === "capture"
                           && modelData.enabled !== false
                           && modelData.id !== root.defaultAction
                  iconText: "󰐃"
                  tooltipText: "Make this the default"
                  size: Style.space(18)
                  foreground: Color.popups.text
                  fontFamily: Style.font.resolvedFamily
                  opacity: 0.7
                  onClicked: root.defaultRequested(modelData.id)
                }

                // Sized-and-aligned children rather than anchored ones:
                // anchors on the children of a positioner are not supported,
                // and a verticalCenter-anchored glyph beside a
                // verticalCenter-anchored Column is how the icon and the label
                // drifted out of line with each other.
                Row {
                  id: rowLayout
                  anchors.fill: parent
                  anchors.leftMargin: root.rowInset
                  anchors.rightMargin: root.rowInset + Style.space(20)
                  spacing: Style.spacing.controlGap

                  Text {
                    width: Style.space(16)
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.glyph || ""
                    color: Color.popups.text
                    font.family: Style.font.resolvedFamily
                    font.pixelSize: Style.font.body
                  }

                  Column {
                    id: entryText
                    // Row owns x; y is ours, and setting it directly avoids
                    // anchoring inside the positioner.
                    y: Math.round((rowLayout.height - height) / 2)
                    spacing: Style.spacing.hairline

                    Text {
                      text: modelData.label
                           + (modelData.id === root.defaultAction ? "  ·  default" : "")
                      color: Color.popups.text
                      font.family: Style.font.resolvedFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      visible: modelData.enabled === false && !!modelData.reason
                      text: modelData.reason || ""
                      color: Color.muted
                      font.family: Style.font.resolvedFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
