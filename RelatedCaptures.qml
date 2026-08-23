import QtQuick
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model

// Related captures: only what the user linked, plus a picker to link more.
//
// Nothing is inferred. Whether two captures are related is a judgement about
// meaning, and scoring shared tags and word overlap either offered everything
// or nothing with no useful middle -- so the plugin does not guess.
Column {
  id: root

  property var service: null
  property string memoryId: ""
  property var linked: []
  property bool picking: false

  signal openMemory(string id)

  spacing: Style.spacing.sm

  Item { id: focusSink }

  function reload() {
    if (!service || !memoryId) return
    service.call(["related", "--id", memoryId], function (code, json) {
      root.linked = (json && json.linked) || []
    })
  }

  function loadCandidates(query) {
    if (!service || !memoryId) return
    var args = ["candidates", "--id", memoryId]
    if (query && query.trim().length) args = args.concat(["--q", query.trim()])
    service.call(args, function (code, json) {
      picker.candidates = (json && json.candidates) || []
    })
  }

  function act(verb, otherId) {
    if (!service) return
    service.call(["link", verb, "--from", root.memoryId, "--to", otherId],
                 function () {
                   root.reload()
                   if (root.picking) root.loadCandidates(picker.query)
                 })
  }

  onMemoryIdChanged: {
    root.picking = false
    reload()
  }

  PanelSectionHeader {
    text: "Related captures"
    foreground: Color.muted
    fontFamily: Style.font.resolvedFamily
  }

  // --- the picker ----------------------------------------------------------
  Column {
    id: picker
    property var candidates: []
    property string query: ""

    width: parent.width
    spacing: Style.spacing.sm
    visible: root.picking

    TextField {
      width: parent.width
      foreground: Color.popups.text
      accent: Color.accent
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.body
      placeholderText: "Search memories to link…"
      onTextChanged: {
        picker.query = text
        pickerDebounce.restart()
      }
      Keys.onEscapePressed: function (event) {
        focusSink.forceActiveFocus()
        event.accepted = true
      }
    }

    Timer {
      id: pickerDebounce
      interval: 180
      onTriggered: root.loadCandidates(picker.query)
    }

    Text {
      visible: picker.candidates.length === 0
      text: "No other memories to link."
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: picker.candidates

      delegate: CursorSurface {
        required property var modelData
        width: picker.width
        height: Style.spacing.popupRowHeight
        bordered: false
        foreground: Color.popups.text

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.act("add", modelData.id)
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.sm
          anchors.rightMargin: Style.spacing.sm
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            color: Color.accent
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: picker.width - Style.space(40)
            text: Model.truncate(modelData.title, 70)
            elide: Text.ElideRight
            color: Color.popups.text
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // --- linked --------------------------------------------------------------
  Grid {
    width: parent.width
    columns: 2
    columnSpacing: Style.spacing.md
    rowSpacing: Style.spacing.md
    visible: root.linked.length > 0

    Repeater {
      model: root.linked
      delegate: RelatedCard {
        required property var modelData
        memory: modelData
        width: (root.width - Style.spacing.md) / 2
        onOpened: root.openMemory(modelData.id)
        onRemoved: root.act("remove", modelData.id)
      }
    }
  }

  // The action, after whatever content exists -- the same shape Collections
  // uses. An empty section then offers the action instead of describing its
  // own emptiness, so neither needs a separate placeholder line.
  // A chip, not a Button: it sits in the same class of inline affordance as
  // Collections' "Add to collection" one section below, and the two were at
  // different heights and text sizes.
  Chip {
    label: root.picking ? "Done" : "+  Link a memory"
    tint: Color.muted
    outlined: true
    interactive: true
    onClicked: {
      root.picking = !root.picking
      if (root.picking) root.loadCandidates("")
    }
  }
}
