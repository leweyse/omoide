import QtQuick
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model

// The whole to-do list of one memory, edited as a list.
//
// The per-item editor handles one to-do's date and reminders; this handles the
// list itself -- add another, retitle the ones that are there, drop the ones that
// are not wanted. Those are list operations, and doing them one dialog at a time
// through the item editor meant reopening it once per to-do.
//
// Rows are staged in `draft` and nothing is written until Save, so Cancel is a
// real undo. `draft` is the single truth: a delete rewrites it rather than
// hiding a delegate, because a hidden delegate and a stale model disagree and
// the model is what Save reads.
FocusScope {
  id: root

  property bool opened: false
  property real scrimRadius: 0
  property var service: null
  property string memoryId: ""

  // [{ id, title }] -- id empty for a row that does not exist yet.
  property var draft: []
  // What was loaded, to diff against on save.
  property var loaded: []

  signal changed()

  function open(items) {
    var rows = []
    var seed = items || []
    for (var i = 0; i < seed.length; i++)
      rows.push({ id: seed[i].id || "", title: seed[i].title || "" })
    root.loaded = rows.slice()
    root.draft = rows
    root.opened = true
    Qt.callLater(function () { addButton.forceActiveFocus() })
  }

  function close() { root.opened = false }

  // Reads the live fields, so a rewrite of `draft` keeps what has been typed.
  function collect() {
    var out = []
    for (var i = 0; i < rows.count; i++) {
      var row = rows.itemAt(i)
      if (!row) continue
      out.push({ id: row.rowId, title: row.field.text })
    }
    return out
  }

  function addRow() {
    var next = root.collect()
    next.push({ id: "", title: "" })
    root.draft = next
    // Focus the row that just appeared, not the button that made it.
    Qt.callLater(function () {
      var last = rows.itemAt(rows.count - 1)
      if (last) last.field.forceActiveFocus()
    })
  }

  function removeRow(i) {
    var next = root.collect()
    if (i < 0 || i >= next.length) return
    next.splice(i, 1)
    root.draft = next
    Qt.callLater(function () { addButton.forceActiveFocus() })
  }

  function save() {
    if (!root.service) return
    var now = root.collect()
    var queue = []

    var seen = ({})
    for (var i = 0; i < now.length; i++) {
      var title = (now[i].title || "").trim()
      if (!title.length) continue          // a blank row is a row never filled in
      if (now[i].id.length) {
        seen[now[i].id] = true
        // Only what actually moved.
        for (var j = 0; j < root.loaded.length; j++)
          if (root.loaded[j].id === now[i].id && root.loaded[j].title !== title)
            queue.push(["item", "edit", "--id", now[i].id, "--title", title])
      } else {
        queue.push(["item", "add", "--memory", root.memoryId,
                    "--kind", "todo", "--title", title])
      }
    }

    // Cancel, not delete: the CLI has no item delete, and a cancelled row keeps
    // its reminders' history while dropping out of every list.
    for (var k = 0; k < root.loaded.length; k++)
      if (!seen[root.loaded[k].id])
        queue.push(["item", "cancel", "--id", root.loaded[k].id])

    if (!queue.length) { root.close(); return }
    root.runQueue(queue, function () {
      root.changed()
      root.close()
    })
  }

  // One at a time: the CLI is a process per call, and firing them together makes
  // the order of writes to one memory undefined.
  function runQueue(queue, done) {
    if (!queue.length) { done(); return }
    var head = queue.shift()
    root.service.call(head, function () { root.runQueue(queue, done) })
  }

  visible: opened

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
  }

  // Somewhere for focus to land that is not a control about to be destroyed.
  Item { id: focusSink }

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(520),
                    parent.width - Style.spacing.panelPadding * 2)
    height: layout.implicitHeight + Style.spacing.panelPadding * 2
    radius: Style.cornerRadius
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
      spacing: Style.space(20)

      Text {
        text: "To-dos"
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: (root.draft || []).length > 0

        Repeater {
          id: rows
          model: root.draft

          delegate: Item {
            id: todoRow
            required property var modelData
            required property int index

            readonly property string rowId: modelData.id || ""
            property alias field: title

            width: parent.width
            height: title.height

            AccentField {
              id: title
              anchors.left: parent.left
              anchors.right: dropRow.left
              anchors.rightMargin: Style.spacing.controlGap
              anchors.verticalCenter: parent.verticalCenter
              escapeTo: focusSink
              text: todoRow.modelData.title || ""
              placeholderText: "What needs doing?"
              foreground: Color.menu.text
              accent: Color.accent
              ringBackdrop: Color.menu.background
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            PanelActionButton {
              id: dropRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              focusable: true
              bordered: true
              iconText: "×"
              tooltipText: "Remove this to-do"
              size: Style.space(24)
              foreground: Color.menu.text
              hoverColor: Color.urgent
              fontFamily: Style.font.menuFamily
              borderSpec: activeFocus
                          ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                          : Border.controlSpec("normal", foreground, foreground)
              onClicked: {
                // Focus away FIRST: this button is about to be destroyed, and a
                // dropped focus takes every Keys handler in the dialog with it.
                addButton.forceActiveFocus()
                root.removeRow(todoRow.index)
              }

              FocusRing {
                sideBars: true
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
      }

      Text {
        visible: (root.draft || []).length === 0
        width: parent.width
        text: "No to-dos yet."
        color: Color.muted
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: parent.width
        height: addButton.height

        Button {
          id: addButton
          anchors.horizontalCenter: parent.horizontalCenter
          focusable: true
          bordered: true
          text: "+  Add a to-do"
          foreground: Color.menu.text
          background: Color.menu.background
          accent: Color.accent
          fontFamily: Style.font.menuFamily
          borderSpec: activeFocus
                      ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                      : Border.controlSpec(hot ? "hover-cursor" : "normal",
                                           foreground, accent)
          onClicked: root.addRow()

          FocusRing {
            sideBars: true
            anchors.fill: parent
            radius: parent.radius
            gap: 1
            hasCursor: parent.activeFocus
            backdrop: Color.menu.background
            hot: false
          }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: Color.menu.text
      }

      Item {
        width: parent.width
        height: actions.height

        Row {
          id: actions
          anchors.right: parent.right
          spacing: Style.spacing.controlGap

          Button {
            focusable: true
            text: "Cancel"
            foreground: Color.menu.text
            background: Color.menu.background
            fontFamily: Style.font.menuFamily
            borderSpec: activeFocus
                        ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                        : Border.controlSpec(hot ? "hover-cursor" : "normal",
                                             foreground, accent)
            onClicked: root.close()

            FocusRing {
              sideBars: true
              anchors.fill: parent
              radius: parent.radius
              gap: 1
              hasCursor: parent.activeFocus
              backdrop: Color.menu.background
              hot: false
            }
          }

          Button {
            focusable: true
            text: "Save"
            selected: true
            foreground: Color.menu.text
            background: Color.menu.background
            accent: Color.accent
            fontFamily: Style.font.menuFamily
            borderSpec: activeFocus
                        ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
                        : Border.controlSpec(selected ? "selected" : "normal",
                                             foreground, accent)
            onClicked: root.save()

            FocusRing {
              sideBars: true
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
    }
  }
}
