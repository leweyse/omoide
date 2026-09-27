import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../common"
import "../components"
import "../dialogs"
import "../views"
import "../MemoryModel.js" as Model
import "../common/Radii.js" as Radii

// The Space dialog.
//
// A centered layer-shell surface rather than a desktop window: that is the
// idiom every first-party Omarchy surface uses (clipboard, emojis, image
// picker, menu), and it is what gets reliable keyboard focus, Esc handling and
// theme integration. A FloatingWindow does not map under Hyprland here.
//
// Destinations are a left rail, driven by `sections`, so a new section is one
// entry there.
Item {
  id: root

  property var service: null
  property bool opened: false
  property string section: "foryou"
  property string memoryId: ""
  property string collectionName: ""

  readonly property string pageTitle: {
    if (root.section === "detail") return "Memory"
    if (root.section === "collection") return root.collectionName
    // For you states what is actually on today rather than naming itself.
    if (root.section === "foryou")
      return Model.digestLine(root.service ? root.service.index.digest : null)
    for (var i = 0; i < root.sections.length; i++)
      if (root.sections[i].id === root.section) return root.sections[i].title
    return ""
  }

  // The card's INNER radius: its outer curve less the border the
  // content sits behind. Overlays layered inside it use this so a
  // square scrim cannot paint across the corners.
  readonly property real cardRadius:
    Math.max(0, Style.cornerRadius - Math.max(1, Style.space(2)))

  // Keyboard focus lives at one of two depths, and this one flag says which:
  // the sidebar, or the page. Not a "mode" -- the sidebar paints a visible
  // cursor whenever it holds the keyboard, so there is nothing invisible to
  // get lost in.
  property bool inContent: false
  property int railCursor: 0

  // An open overlay owns the keyboard, so the dialog's own map goes dormant
  // while one is up. That includes the overflow menu, which has no key handler
  // of its own; without this, Escape would fall through it and shut the dialog.
  readonly property bool overlayOpen:
    itemEditor.opened || blockEditor.opened || imagePreview.opened
    || renamePrompt.opened || overflowMenu.opened
    || confirmDelete.opened || confirmRemove.opened
    || linkPicker.opened || collectionPicker.opened
    || todosEditor.opened

  // Which sidebar row belongs to the page on screen. A memory or a collection
  // was reached through the Library, so that is the row that stays lit.
  function sectionIndex() {
    for (var i = 0; i < root.sections.length; i++)
      if (root.sections[i].id === root.section) return i
    return 1
  }

  readonly property var sections: [
    { id: "foryou",  label: "For you", title: "For you",       glyph: "" },
    { id: "library", label: "Library", title: "Library",       glyph: "" },
    { id: "todos",   label: "Tasks",   title: "Tasks",         glyph: "" }
  ]

  function show(payload) {
    var data = payload || ({})
    if (data.section) root.section = data.section
    if (data.id) {
      root.memoryId = data.id
      root.section = "detail"
      // Arriving from outside -- a notification, a bar click -- so there is no
      // page behind this one. Back goes to the Library, not to whatever
      // collection happened to be open the last time the dialog was used.
      root.memoryOrigin = "library"
      root.memoryOriginCollection = ""
    } else if (!data.section) {
      root.section = "foryou"
    }
    // The sidebar takes the keyboard on every open: you navigate the menu
    // first. The exception is being sent somewhere -- a notification opening a
    // memory -- where focus belongs on the thing you were sent to.
    root.inContent = !!data.id
    root.railCursor = root.sectionIndex()
    root.opened = true
    root.restoreFocus()
  }

  // Landing on a page programmatically -- from a notification, from the item
  // editor's memory link -- has to place focus too, or the page arrives with
  // nothing highlighted and the arrows appear dead.
  function enterContent() {
    root.inContent = true
    root.railCursor = root.sectionIndex()
    root.restoreFocus()
    root.focusPageFirst()
  }

  // Candidates for the link picker. Filtered by the CLI, so typing narrows the
  // list rather than the dialog filtering a stale set.
  function loadCandidates(text) {
    if (!root.service || !root.memoryId.length) return
    var args = ["candidates", "--id", root.memoryId]
    if (text && text.trim().length) args = args.concat(["--q", text.trim()])
    linkPicker.loading = true
    root.service.call(args, function (code, json) {
      linkPicker.loading = false
      var out = []
      var list = (json && json.candidates) || []
      for (var i = 0; i < list.length; i++)
        out.push({ id: list[i].id, label: list[i].title || list[i].id,
                   sublabel: list[i].lede || "" })
      linkPicker.rows = out
    })
  }

  function fileInto(name) {
    if (!root.service || !name.length) return
    root.service.call(["collection", "add", "--name", name,
                       "--memory", root.memoryId],
                      function () { root.service.refresh() })
  }

  // Every collection that exists, minus the ones this memory is already in.
  function collectionChoices() {
    var out = []
    var idx = root.service ? root.service.index : null
    var all = (idx && idx.collections) || []
    var page = viewLoader.item
    var mine = (page && page.memory && page.memory.collections) || []
    for (var i = 0; i < all.length; i++) {
      var taken = false
      for (var j = 0; j < mine.length; j++)
        if (mine[j].name === all[i].name) { taken = true; break }
      if (!taken)
        out.push({ id: all[i].name, label: all[i].name,
                   sublabel: (all[i].count || 0) + " memories" })
    }
    return out
  }

  // Where Back goes from a memory. A memory opened from a collection has to
  // return to that collection, and one opened from Tasks to Tasks -- it was
  // never on the Library grid, so landing there is a jump sideways.
  //
  // Only recorded when arriving from somewhere that is NOT already a memory, so
  // walking a chain of related captures keeps the original origin rather than
  // rewriting it at each hop.
  property string memoryOrigin: "library"
  property string memoryOriginCollection: ""

  function openMemory(id) {
    overflowMenu.close()
    if (root.section !== "detail") {
      root.memoryOrigin = root.section
      root.memoryOriginCollection = root.collectionName
    }
    root.memoryId = id
    root.section = "detail"
    root.enterContent()
  }

  // One way back, shared by Escape and the Back button, so the keyboard and the
  // mouse cannot disagree about where "back" is.
  function goBack() {
    if (root.section === "detail") {
      if (root.memoryOrigin === "collection"
          && root.memoryOriginCollection.length > 0) {
        root.collectionName = root.memoryOriginCollection
        root.section = "collection"
      } else {
        root.section = root.memoryOrigin.length > 0 ? root.memoryOrigin : "library"
      }
      root.enterContent()
      return
    }
    // A collection page always sits under the Library.
    root.section = "library"
    root.enterContent()
  }

  // The title the open detail page loaded, since only that page's menu asks.
  // The menu is owned by the window and only has the id.
  function memoryTitle(id) {
    var page = viewLoader.item
    var memory = page && page.memory
    if (memory && memory.id === id) return memory.title || ""
    return ""
  }

  function openCollection(name) {
    overflowMenu.close()
    root.collectionName = name
    root.section = "collection"
    root.enterContent()
  }

  function openItem(id) {
    // Anywhere except the memory itself: if the capture is not already the page
    // behind this sheet, the sheet offers a way to it. From Tasks, for one, the
    // user has not come from the memory, so the link is what they want.
    itemEditor.showMemoryLink = (root.section !== "detail")
    itemEditor.open(id)
  }

  function requestDelete(id) {
    if (!id || !id.length) return
    confirmDelete.targetId = id
    confirmDelete.open()
  }


  function close() {
    // Everything layered inside goes with it. Left open, an overlay would still
    // be up the next time the dialog appears -- on a memory that may not even
    // be the one it belonged to.
    itemEditor.opened = false
    blockEditor.opened = false
    imagePreview.opened = false
    renamePrompt.opened = false
    overflowMenu.opened = false
    confirmDelete.opened = false
    confirmRemove.opened = false
    helpSheet.opened = false
    linkPicker.opened = false
    collectionPicker.opened = false
    todosEditor.opened = false
    root.opened = false
  }

  function goTo(id) {
    root.section = id
    root.railCursor = root.sectionIndex()
    // Going to a page means acting on it: the keyboard follows, whether the
    // navigation was a sidebar click, Enter on a row, Ctrl+N, or a link in
    // the content. Left or Shift+Tab is the one-key way back to the rail.
    root.inContent = true
    root.focusPageFirst()
    root.restoreFocus()
  }

  // The dialog's whole key map, split out of the handler so the routing reads as
  // one thing rather than as a wall of conditions.
  //
  // Deliberately NOT Keys.priority: Keys.BeforeItem. At the default priority a
  // focused text field consumes printable keys before they reach here, which is
  // what stops "/" and "?" firing mid-query -- and why there is no
  // is-a-field-focused check anywhere below.
  function handleKey(event) {
    // Help is a modal read with nothing to do in it, so any key leaves.
    if (helpSheet.opened) { helpSheet.close(); return true }

    if (event.key === Qt.Key_Escape) {
      // A held Escape auto-repeats. Swallow the repeats, or one press would
      // unwind every layer at once: overlay, sub-page and dialog.
      if (event.isAutoRepeat) return true
      // The page gets first refusal. Library's filter chips are a drill-in, and
      // Esc there has to leave the chips -- if unwind() ran first it would shut
      // the whole dialog instead, one rung too many.
      var esc = viewLoader.item
      if (root.inContent && esc && esc.pageKey && esc.pageKey(event)) return true
      return root.unwind()
    }

    // Everything below is the dialog's map, and an overlay sits on top of the
    // dialog. False, not true, so the key still reaches the overlay.
    if (root.overlayOpen) return false

    if (event.text === "?") { helpSheet.open(); return true }

    // Ctrl, so the digits stay usable and the chord matches what editors and
    // browsers already bind for tabs.
    if ((event.modifiers & Qt.ControlModifier)
        && event.key >= Qt.Key_1
        && event.key < Qt.Key_1 + root.sections.length) {
      root.goTo(root.sections[event.key - Qt.Key_1].id)
      return true
    }

    if (event.text === "/") {
      // Search lives on the Library page, so "/" from anywhere means go there
      // and start typing. callLater because the page does not exist yet at the
      // moment the section changes.
      root.goTo("library")
      Qt.callLater(function () {
        if (viewLoader.item && viewLoader.item.focusInput)
          viewLoader.item.focusInput()
      })
      return true
    }

    return root.inContent ? root.contentKey(event) : root.sidebarKey(event)
  }

  // One rung per press, never skipping. The sheets all close themselves on
  // Escape before it reaches here; the overflow menu cannot, so it is handled.
  function unwind() {
    if (overflowMenu.opened) { overflowMenu.opened = false; return true }
    // Any other overlay is about to handle its own Escape.
    if (root.overlayOpen) return false
    if (root.section === "detail" || root.section === "collection") {
      root.goBack()
      return true
    }
    root.close()
    return true
  }

  function sidebarKey(event) {
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      var n = root.sections.length
      // Wraps. Three destinations is short enough that stopping at the ends is
      // just a key that does nothing.
      root.railCursor =
        (root.railCursor + (event.key === Qt.Key_Down ? 1 : -1) + n) % n
      return true
    }
    // Enter the page. The keypress is CONSUMED here and carries no further: a
    // Right arrow that both entered Tasks and advanced its tab would make one
    // press do two things.
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Right) {
      // Only navigate if this is a DIFFERENT destination. A memory page lights
      // up the Library row, because that is how you got there -- so entering
      // that row again means "back into what I am looking at", not "throw the
      // memory away and show me the grid".
      if (root.railCursor !== root.sectionIndex())
        root.goTo(root.sections[root.railCursor].id)
      else {
        root.inContent = true
        root.focusPageFirst()
      }
      return true
    }
    return false
  }

  // Entering a page puts its cursor on the first item. A page you have entered
  // with nothing highlighted is exactly the invisible mode this model exists to
  // avoid. callLater because changing section swaps the loaded component.
  function focusPageFirst() {
    Qt.callLater(function () {
      if (viewLoader.item && viewLoader.item.focusFirst)
        viewLoader.item.focusFirst()
    })
  }

  function contentKey(event) {
    var page = viewLoader.item

    // Tab cycles the page's regions. What a region IS belongs to the page; all
    // this does is count them and move the index. The page lands its own cursor
    // on the first row, which is the rule everywhere.
    if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
      if (page && page.regionCount > 1)
        page.region = (page.region + 1) % page.regionCount
      return true
    }

    // The page gets first refusal, so a key that means something there -- Left
    // switching a Tasks tab -- is not stolen by the fallback below. A page
    // reports what it did NOT use, which is how "Left at the left edge exits"
    // works without any page having to know the sidebar exists.
    if (page && page.pageKey && page.pageKey(event)) return true

    if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab
        || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
      root.railCursor = root.sectionIndex()
      root.inContent = false
      return true
    }
    return false
  }

  // Every overlay in here takes focus onto its own key catcher when it opens,
  // and none can hand it back, because none knows who had it. So the window
  // takes focus back whenever one closes, or Esc would stay dead afterwards.
  function restoreFocus() {
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omoide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Scrim { anchors.fill: parent }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(1000), panel.width * 0.88)
      height: Math.min(Style.space(720), panel.height * 0.86)
      radius: Style.cornerRadius
      // Opaque on purpose. Omarchy's menu surfaces are translucent, which suits
      // a small command palette but makes a full page of text and thumbnails
      // unreadable over whatever happens to be behind it. The scrim still dims
      // the desktop, so the dialog reads as layered without being see-through.
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                     Color.menu.background.b, 1.0)
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                     Math.max(1, Style.space(2)))

      // Swallow clicks so they do not fall through to the dismiss handler.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        anchors.topMargin: card.borderTop
        anchors.rightMargin: card.borderRight
        anchors.bottomMargin: card.borderBottom
        anchors.leftMargin: card.borderLeft
        focus: true
        Keys.onPressed: function (event) {
          if (root.handleKey(event)) event.accepted = true
        }

        Rectangle {
          id: rail
          width: Style.space(150)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          // A tint of the theme's foreground over the card, not the bar's own
          // colour: the rail is part of this surface, so it should read as a
          // quieter region of it rather than a slab of unrelated chrome. It
          // composites because the card behind it is opaque.
          color: Style.normalFill
          // Inside the border, so the inner curve is the card's radius less
          // the border it sits behind.
          topLeftRadius: Radii.nested(Style.cornerRadius, card.borderLeft)
          bottomLeftRadius: Radii.nested(Style.cornerRadius, card.borderLeft)

          // One padding token so the caption, the rows and the footer all line
          // up on the same inset.
          readonly property real pad: Style.spacing.xl

          // Horizontal padding inside the rail's content: the title, the rows
          // and the footer all carry it. One token because they are all 10 --
          // split it again if they ever need to differ.
          readonly property real contentPadX: Style.spacing.xxl
          // The footer's TOTAL inset from the rail's edges, not an addition to
          // `pad`: it anchors to the rail itself rather than to the padded
          // Column, so this is the whole distance.
          readonly property real footerPadX: Style.spacing.xxl
          // Where a row's label lands once the (currently empty) glyph slot and
          // its gap are accounted for. 4px right of the title.
          readonly property real labelInset: contentPadX + Style.spacing.md

          // Defines the split, which the subtle fill alone does not.
          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Color.menu.border
            opacity: 0.5
          }

          Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            // xl to match every view's outer inset, so the rail caption
            // and the page heading share a baseline.
            anchors.topMargin: Style.spacing.panelPadding
            anchors.leftMargin: rail.pad
            anchors.rightMargin: rail.pad
            spacing: Style.spacing.sm

            // The name, at the hero's weight and size but not a PanelHero:
            // with no icon the hero still applies its 14px label inset, which
            // would put the title right of every row label under it.
            //
            // 10px, the same padding the rows carry. Set explicitly rather than
            // through labelInset, because it is a chosen number here, not a
            // derived one. Changing the rows' padding leaves the title put.
            Text {
              width: parent.width
              leftPadding: rail.contentPadX
              rightPadding: rail.contentPadX
              text: "Omoide"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            // Under the name, as its subtitle: a count belongs with the thing
            // it counts. The footer holds the keyboard hint.
            Text {
              width: parent.width
              leftPadding: rail.contentPadX
              rightPadding: rail.contentPadX
              text: root.service
                    ? (root.service.index.memoryCount || 0) + " memories" : ""
              color: Color.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            // Enrichment is transient, so it appears under the count rather than
            // replacing it -- the count stays true while a capture is running.
            Text {
              width: parent.width
              leftPadding: rail.contentPadX
              rightPadding: rail.contentPadX
              visible: root.service && root.service.enrichingCount > 0
              text: "Enriching "
                    + (root.service ? root.service.enrichingCount : 0) + "…"
              color: Color.accent
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            Item { width: 1; height: Style.spacing.md }

            PanelSeparator {
              width: parent.width
              foreground: Color.menu.text
            }

            Item { width: 1; height: Style.spacing.md }

            Repeater {
              model: root.sections

              delegate: CursorSurface {
                id: railRow
                required property var modelData
                required property int index
                // Named `selected`, not `current`. CursorSurface already has a
                // `current` that its own paint reads, and redeclaring it would
                // shadow that, leaving the keyboard cursor with no look of its
                // own.
                readonly property bool selected: root.sectionIndex() === index

                width: rail.width - rail.pad * 2
                height: Style.spacing.popupRowHeight
                radius: Style.cornerRadius
                // Two states, two channels: `current` is the page you are on,
                // `hasCursor` is where the keyboard is. Both can show at once,
                // on different rows, which is the whole point.
                current: railRow.selected
                hasCursor: !root.inContent && root.railCursor === index
                bordered: false
                foreground: Color.menu.text

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.goTo(modelData.id)
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: rail.contentPadX
                  anchors.rightMargin: rail.contentPadX
                  spacing: Style.spacing.md

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.glyph
                    color: railRow.selected ? Color.accent : Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.subtitle
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    // Underlined as well as tinted. Colour alone is a weak
                    // signal for "the page you are on" when the keyboard cursor
                    // is a fill on a different row entirely.
                    font.underline: railRow.selected
                    color: railRow.selected ? Color.accent : Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.subtitle
                  }
                }
              }
            }
          }

          // The mark lives down here with the count it describes. An Item, not
          // a Row, so the icon can be anchored against the text block without
          // anchoring inside a positioner.
          Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: rail.footerPadX
            anchors.rightMargin: rail.footerPadX
            anchors.bottomMargin: rail.pad
            height: Math.max(footerMark.height, footerText.implicitHeight)

            SpaceIcon {
              id: footerMark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconSize: Style.font.iconLarge
              color: Color.menu.text
              accentColor: Color.accent
              urgentColor: Color.urgent
              // Same precedence as the bar: it is the same mark, so it must not
              // disagree with it.
              mode: root.service && root.service.enrichingCount > 0
                    ? "working"
                    : (root.service && root.service.failedCount > 0
                       ? "failed" : "idle")
            }

            // The keyboard hint, right-aligned opposite the mark. Keyboard
            // navigation nobody can find is not a feature, and this dialog has
            // no menu bar to hang a shortcuts entry off -- so it lives on the
            // key people already try, and this line names that key.
            //
            // Clickable too: most people will discover the list by reading this
            // rather than by guessing that "?" does something.
            Text {
              id: footerText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "?  Keyboard"
              color: hintArea.containsMouse ? Color.menu.text : Color.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body

              MouseArea {
                id: hintArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: helpSheet.open()
              }
            }
          }
        }

        // Its own strip rather than floating in the corner. Anchored over the
        // content, it would cover anything full-width at the top edge, such as
        // the search field.
        Item {
          id: titleBar
          anchors.top: parent.top
          anchors.left: rail.right
          anchors.right: parent.right
          // Tall enough for both, measured independently: the title is inset
          // like the content it heads, the close button sits in the corner.
          // The gap BELOW the title belongs to the view loader, not here: a
          // view's own top inset scrolls away with its content, and the title
          // would touch whatever scrolled up to meet it.
          height: Math.max(Style.spacing.panelPadding + pageHeading.implicitHeight,
                           titleBar.chromeInset + closeButton.height)

          // The close button's inset. Deliberately tighter than the content
          // inset so it reads as window chrome rather than as part of the
          // page, with a nudge off the corner so the glyph does not crowd
          // the card's border.
          readonly property real chromeInset: Style.spacing.lg + Style.space(2)

          // Out of the library and into a memory or a collection is the only
          // navigation this dialog has, so it belongs beside the page title
          // rather than inside the page's own content.
          PanelActionButton {
            id: backButton
            visible: root.section === "detail" || root.section === "collection"
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.panelPadding
            anchors.verticalCenter: pageHeading.verticalCenter
            iconText: "←"
            tooltipText: root.section === "detail"
                         && root.memoryOrigin === "collection"
                         ? "Back to the collection" : "Back"
            size: Style.space(26)
            foreground: Color.menu.text
            fontFamily: Style.font.resolvedFamily
            onClicked: root.goBack()
          }

          // Left inset matches every view's outer inset, so the title lines up
          // with the content beneath it -- unless Back is there, in which case
          // it follows the button.
          Text {
            id: pageHeading
            anchors.left: backButton.visible ? backButton.right : parent.left
            anchors.leftMargin: backButton.visible ? Style.spacing.lg
                                                   : Style.spacing.panelPadding
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.panelPadding
            anchors.right: closeButton.left
            anchors.rightMargin: Style.spacing.lg
            text: root.pageTitle
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
          }

          PanelActionButton {
            id: closeButton
            // In the corner, not aligned to the title: equal top and right
            // insets, deliberately tighter than the content inset so it reads
            // as window chrome rather than as part of the page.
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: titleBar.chromeInset
            anchors.rightMargin: titleBar.chromeInset
            iconText: "✕"
            tooltipText: "Close  (Esc)"
            // A bigger glyph in the same hit area, so the ✕ does not read
            // small.
            fontSize: Style.font.iconLarge
            size: Style.space(22)
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            onClicked: root.close()
          }
        }

        ConfirmSheet {
          id: confirmDelete
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 50
          property string targetId: ""
          onOpenedChanged: if (!opened) root.restoreFocus()
          message: "Delete this memory? Its note, screenshot and to-dos go with it."
          confirmText: "Delete"

          onCanceled: {
            opened = false
            targetId = ""
          }

          onConfirmed: {
            if (targetId.length && root.service)
              root.service.detach(["delete", "--id", targetId])
            opened = false
            targetId = ""
            // Leaving the memory's own page: it is about to stop existing.
            // The id goes too, so nothing can navigate back onto it.
            if (root.section === "detail") {
              root.memoryId = ""
              // Straight to the origin, but never back onto a memory that has
              // just stopped existing.
              root.goBack()
            }
          }
        }

        OverflowMenu {
          id: overflowMenu
          anchors.fill: parent
          z: 35
          onOpenedChanged: if (!opened) root.restoreFocus()
          onChose: function (action, targetId) {
            if (action === "delete") {
              root.requestDelete(targetId)
            } else if (action === "retitle") {
              renamePrompt.open("Memory title",
                                root.memoryTitle(targetId), "memory:" + targetId)
            } else if (action === "rename") {
              renamePrompt.open("Rename collection", targetId, targetId)
            } else if (action === "remove") {
              confirmRemove.targetId = targetId
              confirmRemove.opened = true
            }
          }
        }

        // Renaming a collection. Its own sheet rather than an inline field: the
        // title sits under a Back button and above a grid, and an editable
        // heading there is easy to open by accident.
        PromptSheet {
          id: renamePrompt
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 50
          placeholder: "Collection name"
          onOpenedChanged: if (!opened) root.restoreFocus()
          onCanceled: opened = false
          // Two callers, told apart by a prefix on the target rather than by a
          // second sheet: a collection is keyed by its name, a memory by its id.
          onAccepted: function (value, targetId) {
            if (!root.service || !targetId.length) return
            if (targetId.indexOf("memory:") === 0) {
              root.service.call(["memory", "--id", targetId.slice(7),
                                 "--title", value],
                                function () { root.service.refresh() })
              return
            }
            if (value === targetId) return
            root.service.call(["collection", "rename", "--name", targetId,
                               "--to", value], function () {
              // The page is keyed on the name, so it has to follow the rename
              // or the grid empties out.
              root.collectionName = value
              root.service.refresh()
            })
          }
        }

        // Correcting the agent's own words. It writes through `block set`, which
        // marks the row edited so a later retry cannot silently overwrite it.
        BlockEditor {
          id: blockEditor
          anchors.fill: parent
          z: 50
          scrimRadius: root.cardRadius
          onOpenedChanged: if (!opened) root.restoreFocus()

          function openFor(blockId, blockType, payload) {
            var data = payload || ({})
            if (blockType === "list") {
              blockEditor.open(blockId, blockType, data.heading || "",
                               Model.itemsToLines(data.items || []))
            } else {
              blockEditor.open(blockId, blockType, "", data.text || "")
            }
          }

          onSaved: function (blockId, heading, body) {
            if (!root.service || !blockId.length) return
            var payload = blockEditor.blockType === "list"
                          ? { heading: heading, items: Model.linesToItems(body) }
                          : { text: body.trim() }
            root.service.call(["block", "set", "--id", blockId,
                               "--payload", JSON.stringify(payload)],
                              function () { root.service.refresh() })
          }
        }

        ConfirmSheet {
          id: confirmRemove
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 50
          property string targetId: ""
          onOpenedChanged: if (!opened) root.restoreFocus()
          message: "Remove the collection “" + confirmRemove.targetId
                   + "”? The memories in it are kept — only the collection goes."
          confirmText: "Remove"
          onCanceled: { opened = false; targetId = "" }
          onConfirmed: {
            if (targetId.length && root.service)
              root.service.call(["collection", "delete", "--name", targetId],
                                function () { root.service.refresh() })
            opened = false
            targetId = ""
            // Leaving the collection's own page: it is about to stop existing,
            // so nothing may navigate back onto it.
            root.collectionName = ""
            if (root.memoryOrigin === "collection") {
              root.memoryOrigin = "library"
              root.memoryOriginCollection = ""
            }
            root.section = "library"
          }
        }

        ImagePreview {
          id: imagePreview
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 45
          onOpenedChanged: if (!opened) root.restoreFocus()
          onEditRequested: if (source.length)
            Quickshell.execDetached(["tensaku-edit", source])
        }

        // Linking a memory and filing into a collection share one sheet,
        // because they are the same interaction: type, pick, done.
        // Add, rename and remove across the whole to-do list of one memory. The
        // item editor still owns a single to-do's date and reminders.
        TodosEditor {
          id: todosEditor
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 55
          service: root.service
          onOpenedChanged: if (!opened) root.restoreFocus()
          onChanged: if (root.service) root.service.refresh()
        }

        PickerSheet {
          id: linkPicker
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 55
          title: "Link a memory"
          placeholder: "Search your captures…"
          emptyText: "No other captures to link."
          onOpenedChanged: if (!opened) root.restoreFocus()
          onSearchRequested: function (text) { root.loadCandidates(text) }
          onChose: function (id) {
            if (root.service)
              root.service.call(["link", "add", "--from", root.memoryId,
                                 "--to", id],
                                function () { root.service.refresh() })
            linkPicker.close()
          }
        }

        PickerSheet {
          id: collectionPicker
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 55
          title: "Add to collection"
          placeholder: "Collection name…"
          emptyText: "No collections yet — type a name to make one."
          // A collection you type is a collection you create, so free text is
          // the point here rather than an escape hatch.
          allowFreeText: true
          onOpenedChanged: if (!opened) root.restoreFocus()
          onChose: function (id) { root.fileInto(id); collectionPicker.close() }
          onSubmitted: function (text) { root.fileInto(text); collectionPicker.close() }
        }

        // A window of its own, so the reference can outgrow this card.
        HelpSheet {
          id: helpSheet
          onClosed: root.restoreFocus()
        }

        ItemEditor {
          id: itemEditor
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 40
          service: root.service
          onOpenedChanged: if (!opened) root.restoreFocus()
          onChanged: if (root.service) root.service.refresh()
          onOpenMemory: function (id) { root.openMemory(id) }
        }

        Loader {
          id: viewLoader
          anchors.top: titleBar.bottom
          // The WHOLE gap under the page title, not an addition to one. Views
          // carry no top inset of their own, so the gap is the same at rest and
          // once scrolled.
          anchors.topMargin: Style.spacing.panelPadding
          anchors.bottom: parent.bottom
          anchors.left: rail.right
          anchors.right: parent.right

          sourceComponent: {
            switch (root.section) {
            case "library": return libraryView
            case "todos":      return archiveView
            case "detail":     return detailView
            case "collection": return collectionView
            default:        return forYouView
            }
          }
        }
      }
    }
  }

  Component {
    id: forYouView
    ForYouView {
      service: root.service
      hasKeyboard: root.inContent
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenItem: function (id) { root.openItem(id) }
      onOpenArchive: root.goTo("todos")
    }
  }

  Component {
    id: libraryView
    LibraryView {
      service: root.service
      hasKeyboard: root.inContent
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenCollection: function (name) { root.openCollection(name) }
    }
  }

  Component {
    id: archiveView
    TodoArchive {
      service: root.service
      hasKeyboard: root.inContent
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenItem: function (id) { root.openItem(id) }
    }
  }

  Component {
    id: collectionView
    CollectionDetail {
      service: root.service
      collectionName: root.collectionName
      onOpenMemory: function (id) { root.openMemory(id) }
      onMenuRequested: function (sceneX, sceneY) {
        overflowMenu.openAt(sceneX, sceneY, root.collectionName, [
          { id: "rename", label: "Edit title", glyph: "󰏫" },
          { id: "remove", label: "Remove",     glyph: "󰩹", destructive: true }
        ])
      }
    }
  }

  Component {
    id: detailView
    MemoryDetail {
      service: root.service
      hasKeyboard: root.inContent
      memoryId: root.memoryId
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenItem: function (id) { root.openItem(id) }
      onDeleteMemory: function (id) { root.requestDelete(id) }
      onPreviewImage: function (path) { imagePreview.open(path) }
      onEditBlock: function (blockId, blockType, payload) {
        blockEditor.openFor(blockId, blockType, payload)
      }
      onManageTodos: function (blockId, items) {
        todosEditor.memoryId = root.memoryId
        todosEditor.open(blockId, items)
      }
      onLinkRequested: {
        linkPicker.rows = []
        linkPicker.open()
        root.loadCandidates("")
      }
      onCollectionRequested: {
        collectionPicker.rows = root.collectionChoices()
        collectionPicker.open()
      }
      onRetryEnrichment: function (id) {
        // Detached: the agent takes seconds and must not block the dialog. The
        // CLI marks the memory pending and pings the shell, so the page shows
        // the working state on its own.
        if (root.service) root.service.detach(["enrich", "--id", id])
      }
      onMenuRequested: function (sceneX, sceneY) {
        overflowMenu.openAt(sceneX, sceneY, root.memoryId, [
          { id: "retitle", label: "Edit title", glyph: "󰏫" },
          { id: "delete",  label: "Delete",     glyph: "󰩹", destructive: true }
        ])
      }
    }
  }
}
