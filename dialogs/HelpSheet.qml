import QtQuick
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
FocusScope {
  id: root

  property bool opened: false
  property real scrimRadius: 0

  signal closed()

  function open() {
    root.opened = true
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.closed()
  }

  visible: opened

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
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

  Scrim {
    anchors.fill: parent
    radius: root.scrimRadius
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
      width: Math.min(Style.space(720),
                      parent.width - Style.spacing.panelPadding * 2)
      height: layout.implicitHeight + Style.spacing.panelPadding * 2
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
        spacing: Style.spacing.xxl

        Text {
          text: "Keyboard"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.spacing.huge

          Repeater {
            model: [root.leftGroups, root.rightGroups]

            delegate: Column {
              required property var modelData
              width: (parent.width - Style.spacing.huge) / 2
              spacing: Style.spacing.xxl

              Repeater {
                model: parent.modelData

                delegate: Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.spacing.md

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
                        width: Style.space(84)
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
