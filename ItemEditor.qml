import QtQuick
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model

// A to-do or event, opened from anywhere one is shown.
//
// A card layered over the Space dialog rather than a separate window: clicking
// a to-do should not lose the page you were reading, and the archive and a
// memory both need to reach the same editor.
//
// It is a FORM, not a set of live controls. Every edit is staged locally and
// written only by Save, so a mistyped date can be abandoned by closing the
// sheet. That is the whole reason the fields do not commit as you leave them.
//
// A to-do has no date of its own here. Its time follows its earliest reminder,
// which is what the archive groups on. An event keeps its own Starts, because
// an event's time is the thing itself and its reminders are offsets from it.
Item {
  id: root

  property var service: null
  property bool opened: false
  property string itemId: ""
  property var item: ({ reminders: [] })

  // Shown only where the item was reached without its capture, which is the
  // For you page. From a memory you are already there.
  property bool showMemoryLink: false

  // 0 when this covers a whole screen; the card's inner radius when it
  // is layered inside one.
  property real scrimRadius: 0

  signal changed()
  signal openMemory(string id)

  readonly property bool hasMemoryLink: root.showMemoryLink
                                        && !!(item && item.memoryTitle)
  readonly property bool suggested: !!(item && item.status === "suggested")
  readonly property bool done: !!(item && item.completedAt)
  readonly property bool isEvent: item && item.kind === "event"

  // Seeds the reminder rows. Rebuilt only when a row is added or removed, and
  // always from the delegates' current values, so appending a row never
  // discards what is half-typed in the others.
  property var draftReminders: []

  function open(id) {
    root.itemId = id
    root.opened = true
    root.reload()
    Qt.callLater(function () { editorKeys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.itemId = ""
    root.draftReminders = []
  }

  function reload() {
    if (!service || !itemId) return
    service.call(["item", "get", "--id", itemId], function (code, json) {
      if (!json) return
      root.item = json
      titleField.text = json.title || ""
      var start = Model.dateParts(json.startsAt || json.dueAt)
      startsField.set(start.date, start.time)

      var rows = []
      var reminders = json.reminders || []
      for (var i = 0; i < reminders.length; i++) {
        var parts = Model.dateParts(reminders[i].fireAt)
        rows.push({ id: reminders[i].id, date: parts.date, time: parts.time })
      }
      root.draftReminders = rows
    })
  }

  // Current state of the reminder rows, read straight out of the delegates.
  // The model holds only what they started as; a QML array is not deeply
  // reactive, so writing each keystroke back into it would rebuild the
  // Repeater and take focus away mid-word.
  function collectReminders() {
    var out = []
    for (var i = 0; i < reminderRows.count; i++) {
      var row = reminderRows.itemAt(i)
      if (!row || row.removed) continue
      out.push({ id: row.existingId, date: row.field.date, time: row.field.time })
    }
    return out
  }

  function addReminderRow() {
    var next = root.collectReminders()
    next.push({ id: "", date: "", time: "" })
    root.draftReminders = next
  }

  // One call at a time, in order. Several of these depend on the one before --
  // a changed reminder is a remove followed by an add -- and the CLI rewrites
  // index.json on each, so firing them together would race.
  function runQueue(queue, finished) {
    if (!service || !queue.length) {
      if (finished) finished()
      return
    }
    var next = queue.shift()
    service.call(next, function () { root.runQueue(queue, finished) })
  }

  function save() {
    if (!service || !itemId) return
    var rows = root.collectReminders()
    var queue = []

    var title = titleField.text.trim()
    if (title.length && title !== (root.item.title || ""))
      queue.push(["item", "edit", "--id", root.itemId, "--title", title])

    // What was loaded, so only the rows that actually moved are rewritten.
    var original = ({})
    var loaded = root.item.reminders || []
    for (var i = 0; i < loaded.length; i++) {
      var parts = Model.dateParts(loaded[i].fireAt)
      original[loaded[i].id] = parts.date + " " + parts.time
    }

    // The CLI has no `reminder edit`, so a moved reminder is a remove and an
    // add. Incomplete rows are skipped rather than guessed at.
    var kept = ({})
    for (var j = 0; j < rows.length; j++) {
      var when = Model.toCliWhen(rows[j].date, rows[j].time)
      if (!when.length) continue
      if (rows[j].id.length) {
        kept[rows[j].id] = true
        if (original[rows[j].id] !== rows[j].date + " " + rows[j].time) {
          queue.push(["reminder", "remove", "--id", rows[j].id])
          queue.push(["reminder", "add", "--item", root.itemId, "--at", when])
        }
      } else {
        queue.push(["reminder", "add", "--item", root.itemId, "--at", when])
      }
    }
    for (var id in original)
      if (!kept[id]) queue.push(["reminder", "remove", "--id", id])

    if (root.isEvent) {
      if (startsField.complete)
        queue.push(["item", "edit", "--id", root.itemId, "--at",
                    Model.toCliWhen(startsField.date, startsField.time)])
    } else {
      // Earliest reminder wins. The ISO form sorts lexicographically, so this
      // needs no date parsing.
      var earliest = ""
      for (var k = 0; k < rows.length; k++) {
        var candidate = Model.toCliWhen(rows[k].date, rows[k].time)
        if (candidate.length && (!earliest.length || candidate < earliest))
          earliest = candidate
      }
      queue.push(earliest.length
                 ? ["item", "edit", "--id", root.itemId, "--at", earliest]
                 : ["item", "edit", "--id", root.itemId, "--clear-at"])
    }

    root.runQueue(queue, function () {
      root.changed()
      root.close()
    })
  }

  visible: opened
  z: 50

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
    // Matches the curve of whatever this is layered over. Anchored inside the
    // Space card, a square scrim paints across the card's rounded corners and
    // the dialog looks like it has square ones.
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  BorderSurface {
    id: sheet
    anchors.centerIn: parent
    width: Math.min(Style.space(440), parent.width - Style.spacing.xl * 2)
    height: layout.implicitHeight + Style.spacing.panelPadding * 2
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                   Math.max(1, Style.space(2)))

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: editorKeys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
      }
    }

    Column {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.xl

      // Where this to-do came from, at the top: it is context for everything
      // below, not one of the actions at the bottom. Its rule appears with it,
      // so the header block never leaves a stray line behind.
      Text {
        visible: root.hasMemoryLink
        width: parent.width
        text: root.item.memoryTitle
              ? "in “" + Model.truncate(root.item.memoryTitle, 40) + "”" : ""
        elide: Text.ElideRight
        color: Color.accent
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.openMemory(root.item.memoryId)
            root.close()
          }
        }
      }

      PanelSeparator {
        visible: root.hasMemoryLink
        width: parent.width
        foreground: Color.menu.text
      }

      // No close glyph anywhere up here. Discarding is Cancel, next to Save,
      // where the choice between keeping and dropping the edits is made.
      Column {
        width: parent.width
        spacing: Style.spacing.md

        PanelSectionHeader {
          width: parent.width
          text: root.isEvent ? "Event"
                             : (root.suggested ? "Suggested to-do" : "To-do")
          foreground: Color.menu.text
          fontFamily: Style.font.menuFamily
        }

        TextField {
          id: titleField
          width: parent.width
          foreground: Color.menu.text
          accent: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          placeholderText: "Title"
          Keys.onEscapePressed: function (event) {
            editorKeys.forceActiveFocus()
            event.accepted = true
          }
        }
      }

      // Events only. A to-do's time comes from its earliest reminder.
      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.isEvent

        Text {
          text: "Starts"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        DateTimeField { id: startsField }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          text: "Reminders"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: reminderRows.count === 0
          text: "None."
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          id: reminderRows
          model: root.draftReminders

          delegate: Item {
            id: reminderRow
            required property var modelData

            // Removal is staged like everything else, so closing the sheet
            // brings the row back.
            property bool removed: false
            property string existingId: modelData.id || ""
            property alias field: when

            width: layout.width
            height: removed ? 0 : when.height
            visible: !removed

            DateTimeField {
              id: when
              anchors.left: parent.left
              Component.onCompleted: when.set(modelData.date, modelData.time)
            }

            // Outlined, like every other control on this sheet. A bare glyph
            // floating beside two bordered fields read as decoration rather
            // than something you could press.
            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: when.verticalCenter
              bordered: true
              iconText: "×"
              tooltipText: "Remove this reminder"
              size: Style.space(24)
              foreground: Color.menu.text
              hoverColor: Color.urgent
              fontFamily: Style.font.menuFamily
              onClicked: reminderRow.removed = true
            }
          }
        }

        // A chip, matching "Add to collection" and "Link a memory": all three
        // are the same thing -- an inline control that adds a row.
        Chip {
          label: "+  Add a reminder"
          tint: Color.muted
          outlined: true
          interactive: true
          onClicked: root.addReminderRow()
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: Color.menu.text
      }

      Item {
        width: parent.width
        height: rightActions.height

        // Outlined, so a destructive action does not sit on the sheet looking
        // like the plain text of a link. Urgent accent, so its border and hover
        // read as destructive without the resting state shouting.
        Button {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Delete"
          bordered: true
          foreground: Color.menu.text
          background: Color.menu.background
          accent: Color.urgent
          fontFamily: Style.font.menuFamily
          onClicked: {
            // An action, not an edit: it does not wait for Save.
            root.runQueue([["item", "cancel", "--id", root.itemId]],
                          function () { root.changed(); root.close() })
          }
        }

        Row {
          id: rightActions
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

          // Accepting is its own act, not part of Save: a suggestion becomes a
          // real to-do and picks up an alarm if it has a time.
          Button {
            visible: root.suggested
            text: "Add"
            selected: true
            foreground: Color.menu.text
            background: Color.menu.background
            accent: Color.accent
            fontFamily: Style.font.menuFamily
            onClicked: root.runQueue([["item", "promote", "--id", root.itemId]],
                                     function () { root.changed(); root.close() })
          }

          Button {
            text: "Save"
            selected: !root.suggested
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
