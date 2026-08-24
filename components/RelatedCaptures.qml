import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model

// Related captures: only what the user linked, plus a chip that opens the
// link picker. The picker itself is a dialog owned by SpaceWindow.
//
// Nothing is inferred. Whether two captures are related is a judgement about
// meaning, and scoring shared tags and word overlap either offered everything
// or nothing with no useful middle -- so the plugin does not guess.
Column {
  id: root

  property var service: null
  property string memoryId: ""
  property var linked: []
  // Which linked capture the keyboard is on, or -1.
  property int cursor: -1
  // The cursor sits on the section's own chip when it is one past the last card.
  readonly property bool chipFocused:
    root.cursor >= 0 && root.cursor === (root.linked || []).length

  signal openMemory(string id)
  // The link picker is a dialog owned by the window, so this section only
  // asks for it -- it no longer swaps a search field in under the cursor.
  signal linkRequested()

  spacing: Style.spacing.sm

  Item { id: focusSink }

  function reload() {
    if (!service || !memoryId) return
    service.call(["related", "--id", memoryId], function (code, json) {
      root.linked = (json && json.linked) || []
    })
  }

  function act(verb, otherId) {
    if (!service) return
    service.call(["link", verb, "--from", root.memoryId, "--to", otherId],
                 function () { root.reload() })
  }

  onMemoryIdChanged: reload()

  PanelSectionHeader {
    text: "Related captures"
    foreground: Color.muted
    fontFamily: Style.font.resolvedFamily
  }

  // Two up. The cards carry the thumbnail, so a linked capture is recognised
  // by its artwork the way it is in the library grid -- a column of titles
  // would make "related" read as a list of links rather than of captures.
  Grid {
    id: cards
    width: parent.width
    columns: 2
    spacing: Style.spacing.sm
    visible: (root.linked || []).length > 0

    readonly property real cellWidth:
      Math.floor((width - spacing * (columns - 1)) / columns)

    Repeater {
      model: root.linked || []

      delegate: RelatedCard {
        required property var modelData
        required property int index

        width: cards.cellWidth
        memory: modelData
        // Cards come first, then the chip -- which is why chipFocused is one
        // past the last index.
        hasCursor: root.cursor === index
        onOpened: root.openMemory(modelData.id)
        onRemoved: root.act("remove", modelData.id)
      }
    }
  }

  Chip {
    hasCursor: root.chipFocused
    label: "+  Link a memory"
    tint: Color.muted
    outlined: true
    interactive: true
    onClicked: root.linkRequested()
  }
}
