import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model

// A to-do or event, opened from anywhere one is shown.
//
// A card layered over the Space dialog rather than a separate window: clicking
// a to-do should not lose the page you were reading, and the archive and a
// memory both need to reach the same editor.
//
// It is a form, not a set of live controls. Every edit is staged locally and
// written only by Save, so a mistyped date can be abandoned by closing the
// sheet. The fields do not commit as focus leaves them.
//
// A to-do has no date of its own here. Its time follows its earliest reminder,
// which is what the archive groups on. An event keeps its own Starts, because
// an event's time is the thing itself and its reminders are offsets from it.
//
// A FocusScope root, so focus falls back to the dialog when the focused child
// disappears or declines a key, and the Escape handler below sees keys from
// every control inside.
FocusScope {
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

  // Seeds the reminder rows. Rebuilt whenever a row is added or removed, and
  // always from the delegates' current values, so appending a row never
  // discards what is half-typed in the others.
  property var draftReminders: []

  // False until the first load of a freshly opened dialog has placed focus.
  property bool seeded: false

  function open(id) {
    root.itemId = id
    root.opened = true
    root.seeded = false
    root.reload()
    // The first item, not the key catcher, so something is highlighted and Tab
    // has a place to start. The memory link comes before the To-do field when
    // there is one, matching the reading order.
    // Only for the case where reload() will not run. Testing `seeded` instead
    // would race: callLater fires on the next tick while reload waits on a
    // subprocess, so this fallback would always win and the memory link would
    // never get focus.
    if (!root.service || !root.itemId) {
      Qt.callLater(function () {
        root.seeded = true
        titleField.focusField()
      })
    }
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

      // Focus here, not in open(): hasMemoryLink is derived from `item`, which
      // this callback delivers, and open() runs before the fetch returns.
      //
      // Guarded, because reload() also runs after a save, and re-focusing then
      // would pull the cursor away from whatever the user was doing.
      if (!root.seeded) {
        root.seeded = true
        if (root.hasMemoryLink) memoryLink.forceActiveFocus()
        else titleField.focusField()
      }
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
      if (!row) continue
      out.push({ id: row.existingId, date: row.field.date, time: row.field.time })
    }
    return out
  }

  function addReminderRow() {
    var next = root.collectReminders()
    next.push({ id: "", date: "", time: "" })
    root.draftReminders = next
  }

  // Drops the row from the model, not by hiding its delegate, so the view and
  // the model never disagree about which rows exist.
  //
  // Collecting first preserves whatever the other rows currently have typed in
  // them, which a plain splice on draftReminders would discard.
  function removeReminderRow(i) {
    var next = root.collectReminders()
    if (i < 0 || i >= next.length) return
    next.splice(i, 1)
    root.draftReminders = next
  }

  // One call at a time, in order. Several depend on the one before (a changed
  // reminder is a remove followed by an add), and each one ends by making the
  // service pull a new index, so firing them together would race.
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

  // Escape, on the root, because key events travel up the focused item's
  // parent chain and SpaceWindow's unwind() leaves an open overlay to close
  // itself. A catcher beside the content would miss keys from a focused button.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
  }
  z: 50

  Scrim {
    anchors.fill: parent
    // Matches the curve of whatever this is layered over. Anchored inside the
    // Space card, a square scrim paints across the card's rounded corners and
    // the dialog looks like it has square ones.
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  BorderSurface {
    id: sheet
    anchors.centerIn: parent
    width: Math.min(Style.space(440), parent.width - Style.spacing.xxl * 2)
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

      // Where this to-do came from, at the top: it is context for everything
      // below, not one of the actions at the bottom. Its rule appears with it,
      // so the header block never leaves a stray line behind.
      //
      // Accepting a suggestion sits out here at the far right rather than in the
      // bottom row, because it is not an edit: it changes what the item IS, and
      // the bottom row is Cancel and Save for the fields. An Item, not a Row, so
      // a long title elides against the button instead of shoving it off the
      // edge.
      Item {
        visible: root.hasMemoryLink || root.suggested
        width: parent.width
        height: Math.max(memoryLink.implicitHeight, acceptButton.height)

        Text {
          id: memoryLink
          visible: root.hasMemoryLink
          // A real tab stop, not just a clickable label: it is the first thing
          // in the dialog, so the keyboard has to be able to reach it.
          activeFocusOnTab: root.hasMemoryLink
          // Underlined rather than boxed. It is a link, and the text is already
          // the accent colour, so an accent rule under it reads as focus without
          // pretending to be a button or shifting the layout.
          font.underline: memoryLink.activeFocus
          Keys.onReturnPressed: function (event) {
            root.openMemory(root.item.memoryId)
            root.close()
            event.accepted = true
          }
          Keys.onEnterPressed: function (event) {
            root.openMemory(root.item.memoryId)
            root.close()
            event.accepted = true
          }
          anchors.left: parent.left
          anchors.right: acceptButton.visible ? acceptButton.left : parent.right
          anchors.rightMargin: acceptButton.visible ? Style.spacing.lg : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.item.memoryTitle
                ? "in “" + Model.truncate(root.item.memoryTitle, 40) + "”" : ""
          elide: Text.ElideRight
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.openMemory(root.item.memoryId)
              root.close()
            }
          }
        }

        // Outlined, matching the reminder's remove button on the same sheet.
        PanelActionButton {
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
          // focusBorderAlpha, which reads as grey. This type has no `selected`
          // or `accent`, only foreground and `bordered`.
          borderSpec: activeFocus
                      ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                      : (bordered
                         ? Border.controlSpec("normal", foreground, foreground)
                         : Border.none())
          id: acceptButton
          visible: root.suggested
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          bordered: true
          iconText: "+"
          tooltipText: "Add to-do"
          size: Style.space(24)
          foreground: Color.menu.text
          hoverColor: Color.accent
          fontFamily: Style.font.menuFamily
          onClicked: root.runQueue([["item", "promote", "--id", root.itemId]],
                                   function () { root.changed(); root.close() })
        }
      }

      PanelSeparator {
        visible: root.hasMemoryLink || root.suggested
        width: parent.width
        foreground: Color.menu.text
      }

      // No close glyph anywhere up here. Discarding is Cancel, next to Save,
      // where the choice between keeping and dropping the edits is made.
      Column {
        width: parent.width
        spacing: Style.spacing.lg

        PanelSectionHeader {
          width: parent.width
          text: root.isEvent ? "Event"
                             : (root.suggested ? "Suggested to-do" : "To-do")
          foreground: Color.menu.text
          fontFamily: Style.font.menuFamily
        }

        // Multi-line, growing to three. A to-do's title is often a sentence,
        // and a one-line field would scroll its start out of view while the end
        // is edited.
        AccentTextArea {
          id: titleField
          escapeTo: editorKeys
          width: parent.width
          maxLines: 3
          foreground: Color.menu.text
          accent: Color.accent
          ringBackdrop: Color.menu.background
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          placeholderText: "Title"
        }
      }

      // Events only. A to-do's time comes from its earliest reminder.
      Column {
        width: parent.width
        spacing: Style.spacing.lg
        visible: root.isEvent

        Text {
          text: "Starts"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        DateTimeField { id: startsField; escapeTo: editorKeys }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.lg

        Text {
          text: "Reminders"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        Text {
          visible: reminderRows.count === 0
          text: "None."
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          id: reminderRows
          model: root.draftReminders

          delegate: Item {
            id: reminderRow
            required property var modelData
            required property int index

            property string existingId: modelData.id || ""
            property alias field: when

            width: layout.width
            height: when.height

            DateTimeField {
              escapeTo: editorKeys
              id: when
              anchors.left: parent.left
              Component.onCompleted: when.set(modelData.date, modelData.time)
            }

            // Outlined, like every other control on this sheet, so it reads as
            // something to press rather than decoration.
            PanelActionButton {
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
              // focusBorderAlpha, which reads as grey. This type has no
              // `selected` or `accent`, only foreground and `bordered`.
              borderSpec: activeFocus
                          ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                          : (bordered
                             ? Border.controlSpec("normal", foreground, foreground)
                             : Border.none())
              anchors.right: parent.right
              anchors.verticalCenter: when.verticalCenter
              bordered: true
              iconText: "×"
              tooltipText: "Remove this reminder"
              size: Style.space(24)
              foreground: Color.menu.text
              hoverColor: Color.urgent
              fontFamily: Style.font.menuFamily
              onClicked: {
                // Focus first, then hide. This button has focus, and an
                // invisible item cannot hold it: Qt drops it, and with nothing
                // focused no Keys handler in the dialog fires, Escape included.
                //
                // The Add button, not the key catcher: having just removed a
                // row, the next thing within reach should be adding one.
                addReminderButton.forceActiveFocus()
                root.removeReminderRow(reminderRow.index)
              }
            }
          }
        }

        // A chip, matching "Add to collection" and "Link a memory": all three
        // are an inline control that adds a row.
        // An Item, so the button can be given room above it. A Column
        // spacing applies to every gap equally; this one gap wants to be bigger,
        // because the button is an action under a list rather than another row.
        Item {
          width: parent.width
          height: addReminderButton.height + Style.spacing.xxl
        
          DialogButton {
            id: addReminderButton
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            focusable: true
            text: "+  Add a reminder"
            foreground: Color.menu.text
            background: Color.menu.background
            accent: Color.accent
            fontFamily: Style.font.menuFamily
            onClicked: root.addReminderRow()
        
            FocusRing {
              diagonalCorners: true
              anchors.fill: parent
              radius: parent.radius
              gap: 1
              hasCursor: parent.activeFocus
              backdrop: Color.menu.background
              hot: false
            }
          }
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
        DialogButton {
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
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Delete"
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

          DialogButton {

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



            text: "Cancel"
            foreground: Color.menu.text
            background: Color.menu.background
            fontFamily: Style.font.menuFamily
            onClicked: root.close()
          }

          DialogButton {

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



            text: "Save"
            // Primary on a suggestion too: accepting lives in the header, so it
            // does not compete with Save down here.
            selected: true
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
