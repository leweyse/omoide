import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../common"

// The keyboard reference, opened with "?".
//
// Keyboard navigation nobody can discover is dead weight, and this dialog has no
// menu bar to hang a "Shortcuts" entry off. So the list lives behind the key
// people already try, and the rail footer names that key.
//
// Two columns, and everything fits without scrolling. A single scrolling column
// hid half the list behind a gesture nobody could tell was available -- and a
// reference you have to discover twice is not a reference.
//
// Any key closes it. It answers one question and there is nothing to do here
// once answered, so making the reader hunt for the right key to leave would be a
// joke at their expense.
//
// A FocusScope rather than a plain Item: a scope keeps activeFocus when the child
// holding it disappears or declines a key, and being the root puts it on the
// parent chain of everything inside, so the Escape handler sees keys wherever
// focus actually sits.
// Its own layer-shell window, not an overlay inside the Space card: the card
// clamped the sheet to the dialog's height, and a reference that grows past
// its host deserves the screen as its ceiling, the way compose does.
Item {
  id: root

  property bool opened: false

  signal closed()

  function open() {
    root.opened = true
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.closed()
  }

  // Grouped, because a flat list of twenty-seven chords is a wall. The groups
  // follow the model itself: where you are, then how you move, then what each
  // page adds on top.
  //
  // Every line describes something that actually works -- written from the key
  // handlers, not from the plan. A help sheet listing an aspiration is worse
  // than no help sheet.
  readonly property var groups: [
    {
      title: "Getting around",
      rows: [
        { keys: "Ctrl 1…3", what: "For you, Library, Tasks" },
        { keys: "/",        what: "Search the library" },
        { keys: "?",        what: "This list" },
        { keys: "Esc",      what: "Back one step, then close" }
      ]
    },
    {
      title: "The sidebar",
      rows: [
        { keys: "↑  ↓",      what: "Move through the destinations" },
        { keys: "Enter  →",  what: "Enter the page" },
        { keys: "←",         what: "From a page, back to the sidebar" },
        { keys: "Shift Tab", what: "Also back to the sidebar" }
      ]
    },
    {
      title: "Inside a page",
      rows: [
        { keys: "Tab",     what: "Next section on this page" },
        { keys: "↑ ↓ ← →", what: "Move within the section" },
        { keys: "Enter",   what: "Open what the cursor is on" },
        { keys: "Space",   what: "Toggle a to-do, or accept a suggestion" }
      ]
    },
    {
      title: "For you",
      rows: [
        { keys: "←  →", what: "Along the events" },
        { keys: "↓",    what: "Off the events, into the tasks" }
      ]
    },
    {
      title: "Library",
      rows: [
        { keys: "↓",     what: "From a tile into the grid below it" },
        { keys: "f",     what: "Jump to the filter chips" },
        { keys: "Enter", what: "Toggle the focused filter" },
        { keys: "Esc",   what: "Leave the filters, then search" }
      ]
    },
    {
      title: "Tasks",
      rows: [
        { keys: "←  →",  what: "Switch tab: Upcoming, Past, Completed" },
        { keys: "Tab",   what: "Rows ⇄ Suggested, on Upcoming" },
        { keys: "↑  ↓",  what: "Move through the rows" },
        { keys: "Space", what: "Toggle done, without opening it" },
        { keys: "Enter", what: "Open the task" }
      ]
    },
    {
      title: "A memory",
      rows: [
        { keys: "↑  ↓",  what: "Walk the cards; the page follows" },
        { keys: "Enter", what: "Edit, preview, open a link, or step into a to-do list" },
        { keys: "Space", what: "Toggle a to-do, once you are in the list" },
        { keys: "Esc",   what: "Leave the to-do list, back to the card" }
      ]
    },
    {
      title: "Dialogs",
      rows: [
        { keys: "Tab",   what: "Next field or button" },
        { keys: "↑  ↓",  what: "Through a picker's results" },
        { keys: "Enter", what: "Confirm, or pick the result" },
        { keys: "Esc",   what: "Leave the field, then close" }
      ]
    }
  ]

  // Split for balance, not down the middle of the array: the first four groups
  // carry 14 rows, the last four 17. No boundary gives an even split, and moving
  // Library across makes it 18/13 -- worse, and it would break the reading order
  // of general-then-per-page. A short right column is the lesser cost.
  readonly property int splitAt: 4
  readonly property var leftGroups: root.groups.slice(0, root.splitAt)
  readonly property var rightGroups: root.groups.slice(root.splitAt)

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omoide-help"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

  Scrim {
    anchors.fill: parent
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: root.opened

    Keys.onPressed: function (event) {
      root.close()
      event.accepted = true
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(760),
                      parent.width - Style.gapsOut * 2)
      height: Math.min(layout.implicitHeight + Style.spacing.panelPadding * 2,
                       parent.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                     Color.menu.background.b, 1.0)
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                     Math.max(1, Style.space(2)))

      MouseArea { anchors.fill: parent; onClicked: root.close() }

      Column {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.huge

        Text {
          text: "Keyboard"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.space(28)

          Repeater {
            model: [root.leftGroups, root.rightGroups]

            delegate: Column {
              required property var modelData
              width: (parent.width - Style.space(28)) / 2
              spacing: Style.spacing.huge

              Repeater {
                model: parent.modelData

                delegate: Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.spacing.lg

                  Text {
                    text: modelData.title
                    color: Color.muted
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                    font.capitalization: Font.AllUppercase
                  }

                  Repeater {
                    model: modelData.rows

                    // An Item, not a Row: the chord column is a fixed width so
                    // every description starts on the same edge, which a Row
                    // cannot do.
                    delegate: Item {
                      required property var modelData
                      width: parent.width
                      height: Math.max(chord.implicitHeight, what.implicitHeight)

                      Text {
                        id: chord
                        width: Style.space(96)
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: modelData.keys
                        color: Color.accent
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                      }

                      Text {
                        id: what
                        anchors.left: chord.right
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: modelData.what
                        wrapMode: Text.WordWrap
                        color: Color.menu.text
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        lineHeight: 1.25
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Press any key to close."
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
  }
}
