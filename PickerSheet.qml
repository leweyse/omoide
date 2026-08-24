import QtQuick
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model

// One dialog for "type something, pick from a list".
//
// Both things it serves -- linking a memory and filing into a collection -- were
// inline modes that swapped UI in place. As dialogs they stop shifting the page
// under the cursor, and focus containment comes for free: the sheet takes the
// keyboard, arrows walk the rows, Esc leaves.
//
// The owner supplies `rows` and reloads them when `query` changes; this component
// owns no data of its own.
// A FocusScope, not a plain Item.
//
// A scope keeps activeFocus when the child holding it disappears or declines a
// key: focus falls back to the scope instead of vanishing. Without that, a
// focused control being hidden -- a reminder row removed by its own delete
// button -- or a field swallowing Escape left NOTHING focused, and with nothing
// focused no Keys handler in the dialog could fire. The keyboard died and no
// number of Escapes brought it back.
//
// Being the root also puts it on the parent chain of every control inside, so
// the Escape handler below sees keys wherever focus actually sits.
FocusScope {
  id: root

  property bool opened: false
  property real scrimRadius: 0

  property string title: ""
  property string placeholder: ""
  // [{ id, label, sublabel }]
  property var rows: []
  // When true, Enter on a non-empty query that matches no row submits the text
  // itself -- that is how a brand new collection gets created.
  property bool allowFreeText: false
  property string emptyText: "Nothing to choose from."

  property string query: ""
  // Which row the keyboard is on, or -1 while the text field owns it.
  property int cursor: -1

  // NOT `queryChanged`: `property string query` already generates that, and
  // redeclaring it is a load-time duplicate-signal error.
  signal searchRequested(string text)
  signal chose(string id)
  signal submitted(string text)

  function open() {
    root.query = ""
    root.cursor = -1
    field.text = ""
    root.opened = true
    Qt.callLater(function () { field.forceActiveFocus() })
  }

  function close() { root.opened = false }

  // Rebuilt whenever the owner replaces `rows`: an index into the previous set
  // would point at a different row, or past the end.
  onRowsChanged: root.cursor = -1

  visible: opened

  // A place to park focus, inside the scope so it stays on the parent chain.
  //
  // NOT the scope root itself: a FocusScope given focus delegates it back to the
  // child it last had, so `escapeTo: root` bounced straight back to the text
  // field, whose handler accepted the key again -- Escape appeared to do nothing
  // at all. A plain Item holds focus without forwarding it, and keys from it
  // still bubble up to the root handler below. Zero-sized, so it cannot affect
  // layout or swallow a click.
  Item { id: focusSink }

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  // On the ROOT of the card, so it catches the key wherever focus sits. An inner
  // catcher beside the content is never on the focused item's parent chain.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(440),
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
      // Title, field and results are three sections, not three controls, so
      // they get a section-sized gap. At xl (10) the heading sat on the field
      // and the field on the results.
      spacing: Style.space(20)

      Text {
        text: root.title
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      AccentField {
        id: field
        width: parent.width
        placeholderText: root.placeholder
        foreground: Color.menu.text
        accent: Color.accent
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        onTextChanged: {
          root.query = text
          debounce.restart()
        }

        // Typing must not launch one CLI process per keystroke.
        Timer {
          id: debounce
          interval: 180
          onTriggered: root.searchRequested(root.query)
        }

        // The field keeps focus throughout, so it drives the list rather than
        // handing focus over: typing and picking stay one continuous motion.
        Keys.onDownPressed: function (event) {
          root.moveCursor(1)
          event.accepted = true
        }

        Keys.onUpPressed: function (event) {
          root.moveCursor(-1)
          event.accepted = true
        }

        // Esc releases the field first, exactly as it does in every other
        // dialog; the scope root then takes the next one and closes.
        escapeTo: focusSink

        Keys.onReturnPressed: function (event) {
          root.commit()
          event.accepted = true
        }
      }

      Text {
        visible: (root.rows || []).length === 0
        width: parent.width
        text: root.emptyText
        color: Color.muted
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }

      Column {
        width: parent.width
        spacing: Style.spacing.xs
        // Invisible, not merely empty: a zero-height Column still takes a
        // spacing slot from its parent, which left 20px of dead air under the
        // "nothing to choose from" line.
        visible: (root.rows || []).length > 0

        Repeater {
          model: root.rows || []

          delegate: CursorSurface {
            id: pick
            required property var modelData
            required property int index

            width: parent.width
            height: Math.max(Style.spacing.popupRowHeight,
                             rowText.implicitHeight + Style.spacing.md * 2)
            radius: Style.cornerRadius
            hasCursor: root.cursor === index
            bordered: false
            foreground: Color.menu.text

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.cursor = pick.index
              onClicked: root.chose(pick.modelData.id)
            }

            Column {
              id: rowText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.md
              anchors.rightMargin: Style.spacing.md
              spacing: 0

              Text {
                width: parent.width
                text: pick.modelData.label || ""
                elide: Text.ElideRight
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }

              Text {
                visible: text.length > 0
                width: parent.width
                text: pick.modelData.sublabel || ""
                elide: Text.ElideRight
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }

  // Arrows and Enter once the list has the cursor. Up off the first row hands the
  // keyboard back to the field, so typing and picking are one continuous motion.
  Keys.onUpPressed: function (event) { root.moveCursor(-1); event.accepted = true }
  Keys.onDownPressed: function (event) { root.moveCursor(1); event.accepted = true }

  // -1 means "the field owns the keyboard". Up off the first row returns there,
  // so you can go back to typing without reaching for the mouse.
  function moveCursor(d) {
    var n = (root.rows || []).length
    if (n === 0) { root.cursor = -1; return }
    // Only Down enters the list. stepList treats -1 as "unset" and would have
    // Up jump straight to the LAST row, which reads as the cursor teleporting
    // when all you did was press Up in the text field.
    if (root.cursor < 0 && d < 0) return
    var moved = Model.stepList(n, root.cursor, d)
    if (moved === null) {
      if (d < 0) { root.cursor = -1; field.forceActiveFocus() }
      return
    }
    root.cursor = moved
  }

  Keys.onReturnPressed: function (event) {
    root.commit()
    event.accepted = true
  }

  function commit() {
    var list = root.rows || []
    if (root.cursor >= 0 && root.cursor < list.length) {
      root.chose(list[root.cursor].id)
      return
    }
    // Nothing highlighted: a typed name creates, if the caller allows it.
    if (root.allowFreeText && root.query.trim().length > 0)
      root.submitted(root.query.trim())
  }
}
