import QtQuick
import qs.Commons
import "blocks" as Blocks
import "MemoryModel.js" as Model

// type -> delegate. A block whose type this build does not know renders as
// nothing rather than erroring, so a memory written by a newer version of the
// plugin still opens.
Column {
  id: renderer

  property var memory: ({})
  property var service: null
  signal changed()
  signal openItem(var item)
  signal previewImage(string path)
  // The block the user wants to correct, handed up whole: the page owns the
  // editor, so it needs the id, the type and the current payload.
  signal editBlock(string blockId, string blockType, var payload)

  // Which block types this instance draws, so a page can put some blocks above
  // its title and the rest below without reordering stored rows. `only` empty
  // means everything; `except` always wins.
  property var only: []
  property var except: []

  readonly property var shownBlocks: {
    var all = (renderer.memory && renderer.memory.blocks) || []
    var out = []
    for (var i = 0; i < all.length; i++) {
      var type = all[i].type
      if (renderer.only.length > 0 && renderer.only.indexOf(type) < 0) continue
      if (renderer.except.indexOf(type) >= 0) continue
      out.push(all[i])
    }
    return out
  }

  // An empty Column still claims a spacing slot from its parent, so an
  // instance with nothing to draw has to be invisible, not merely zero-height.
  visible: renderer.shownBlocks.length > 0

  spacing: Style.spacing.xl

  function itemById(id) {
    var items = (memory && memory.items) || []
    for (var i = 0; i < items.length; i++)
      if (items[i].id === id) return items[i]
    return null
  }

  function itemsFor(block) {
    var ids = (block.payload && block.payload.item_ids) || []
    var out = []
    for (var i = 0; i < ids.length; i++) {
      var found = renderer.itemById(ids[i])
      if (found) out.push(found)
    }
    return out
  }

  Repeater {
    model: renderer.shownBlocks

    delegate: Loader {
      id: slot
      required property var modelData
      width: renderer.width
      active: Model.isRenderable(modelData.type)

      sourceComponent: {
        switch (modelData.type) {
        case "source":  return sourceCard
        case "image":   return imageCard
        case "note":    return noteCard
        case "summary": return summaryCard
        case "list":    return listCard
        case "todos":   return todosCard
        case "event":   return eventCard
        case "text":
        case "quote":
        case "code":    return textCard
        default:        return null
        }
      }

      // Bindings, not assignments in onLoaded. onLoaded fires once per load, so
      // anything pushed there is frozen at that moment: ticking a to-do
      // reloaded the memory and reassigned `renderer.memory`, but the block kept
      // the item array it was handed when it first appeared, so the check box
      // never filled in.
      //
      // A Binding applies itself when the target appears AND whenever the value
      // changes, which is what a re-read needs. Each reads renderer.memory
      // explicitly so the dependency is unambiguous.
      Binding {
        target: slot.item
        property: "payload"
        value: slot.modelData.payload || ({})
      }

      Binding {
        target: slot.item
        property: "blockId"
        value: slot.modelData.id || ""
      }

      Binding {
        target: slot.item
        property: "blockType"
        value: slot.modelData.type || ""
      }

      Binding {
        target: slot.item
        property: "service"
        value: renderer.service
      }

      Binding {
        target: slot.item
        property: "items"
        when: slot.modelData.type === "todos"
        value: renderer.memory ? renderer.itemsFor(slot.modelData) : []
      }

      Binding {
        target: slot.item
        property: "item"
        when: slot.modelData.type === "event"
        value: renderer.memory
               ? renderer.itemById((slot.modelData.payload || {}).item_id) : null
      }
    }
  }

  Component { id: sourceCard;  Blocks.SourceBlock {} }
  Component {
    id: imageCard
    Blocks.ImageBlock {
      onPreviewRequested: function (path) { renderer.previewImage(path) }
    }
  }
  Component { id: noteCard;    Blocks.NoteBlock {} }
  Component {
    id: summaryCard
    Blocks.SummaryBlock {
      onEditRequested: renderer.editBlock(blockId, blockType, payload)
    }
  }
  Component {
    id: listCard
    Blocks.ListBlock {
      onEditRequested: renderer.editBlock(blockId, blockType, payload)
    }
  }
  Component {
    id: textCard
    Blocks.TextBlock {
      onEditRequested: renderer.editBlock(blockId, blockType, payload)
    }
  }

  Component {
    id: todosCard
    Blocks.TodosBlock {
      onChanged: renderer.changed()
      onOpenItem: function (item) { renderer.openItem(item) }
    }
  }

  Component {
    id: eventCard
    Blocks.EventBlock {
      onChanged: renderer.changed()
      onOpenItem: function (item) { renderer.openItem(item) }
    }
  }
}
