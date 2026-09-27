import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../components"

// The bar icon's menu: the capture modes, plus the two destinations.
//
// An unavailable action is shown disabled with the reason rather than hidden,
// so "why can't I record a voice note" has an answer on screen.
Item {
  id: root

  property QtObject bar: null
  // The bar widget this menu belongs to. The bar coordinates popouts by object
  // identity against the item it loaded from the manifest, so that item, not
  // this one, is what the panel registers. Falls back to `root` so the menu
  // still works standalone.
  property Item owner: null
  property Item anchorItem: null
  property var service: null
  property string defaultAction: "screenshot"

  signal defaultRequested(string action)

  // One inset for both axes of a row, so the highlight is padded evenly.
  readonly property real rowInset: Style.spacing.xl

  readonly property bool opened: panel.open
  // Fails closed: a missing flag means unavailable. Better to hide an action
  // that would have worked than to offer one that cannot.
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

  // No requestPopout/releasePopout here: KeyboardPanel does that bookkeeping
  // from its own `open` change, keyed by `owner`. Doing it again here would
  // register this item instead of the widget. Closing for a panel switch
  // belongs to the owner too.
  function open() {
    root.cursor = 0
    panel.open = true
  }

  function close() {
    panel.open = false
  }

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
      // takes only the binary and drops the subcommand.
      service.showSettings()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.owner || root
    bar: root.bar
    open: false
    focusTarget: keys
    // The width every first-party panel uses, so this reads as one of them.
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

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
      // PanelKeyCatcher emits both returnRequested and activateRequested for
      // Enter. Handle only one, or every entry runs twice.
      onActivateRequested: root.activate(root.entries[root.cursor])
      onTabRequested: function (direction) {
        if (root.owner && typeof root.owner.switchPanel === "function")
          root.owner.switchPanel(direction)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(2)

        // Every other plugin panel opens with one of these, so the menu says
        // whose it is. The icon is the bar mark itself, in its current state.
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

        Item { width: 1; height: Style.spacing.md }

        PanelSeparator {
          width: parent.width
          foreground: Color.popups.text
        }

        Item { width: 1; height: Style.spacing.md }

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
                // Rows with a reason line are two lines tall, and popupRowHeight
                // is a single-line metric.
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

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: root.rowInset
                  anchors.verticalCenter: parent.verticalCenter
                  visible: modelData.id === root.defaultAction
                  text: "default"
                  color: Color.popups.text
                  font.family: Style.font.resolvedFamily
                  font.pixelSize: Style.font.subtitle
                }

                // Sets the default capture mode rather than running it, so it
                // is changeable from the same place the modes are listed.
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
                // and vertically centred anchors let the icon and the label
                // drift out of line.
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
                    font.pixelSize: Style.font.subtitle
                  }

                  Column {
                    id: entryText
                    // Row owns x; y is ours, and setting it directly avoids
                    // anchoring inside the positioner.
                    y: Math.round((rowLayout.height - height) / 2)
                    spacing: Style.spacing.xxs

                    Text {
                      text: modelData.label
                      textFormat: Text.PlainText
                      color: Color.popups.text
                      font.family: Style.font.resolvedFamily
                      font.pixelSize: Style.font.subtitle
                    }

                    Text {
                      visible: modelData.enabled === false && !!modelData.reason
                      text: modelData.reason || ""
                      textFormat: Text.PlainText
                      color: Color.muted
                      font.family: Style.font.resolvedFamily
                      font.pixelSize: Style.font.body
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
