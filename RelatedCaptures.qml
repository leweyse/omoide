import QtQuick
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model

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

  Chip {
    hasCursor: root.chipFocused
    label: "+  Link a memory"
    tint: Color.muted
    outlined: true
    interactive: true
    onClicked: root.linkRequested()
  }
}
