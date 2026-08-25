import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "dialogs"

// One icon. Left-click toggles the action menu, right-click opens the library.
//
// No click captures directly. A capture is a destructive-ish, interactive thing
// -- it grabs the pointer for a region pick -- and having that on the primary
// click meant a misclick on the bar started one. The menu names every mode
// instead, so a capture is always chosen rather than triggered.
//
// The icon is a small state machine driven by the service's index cache, so
// every monitor's copy animates together without any broadcast plumbing.
BarWidget {
  id: root

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
                                 ? bar.shell.serviceFor("leweyse.omoide") : null

  readonly property string defaultAction: setting("defaultAction", "screenshot")
  readonly property int enriching: service ? service.enrichingCount : 0
  readonly property int failed: service ? service.failedCount : 0
  readonly property int todos: service ? service.openTodoCount : 0
  readonly property int dueToday: service ? service.dueTodayCount : 0

  readonly property bool capturing: service ? service.capturing : false
  readonly property bool working: enriching > 0
  readonly property bool broken: !working && failed > 0

  // Capturing outranks everything: it is the only state the user is actively
  // waiting on. Then enrichment, then a failure worth noticing.
  readonly property string iconMode: capturing ? "capturing"
                                   : (working ? "working"
                                   : (broken ? "failed" : "idle"))

  implicitWidth: vertical ? barSize : button.implicitWidth
  implicitHeight: button.implicitHeight

  // The chooser lives on the service, the setting lives on this widget: push
  // it across whenever either side appears or the user changes it.
  function pushDefaultAction() {
    if (service) service.defaultAction = root.defaultAction
  }
  onDefaultActionChanged: pushDefaultAction()
  onServiceChanged: pushDefaultAction()
  Component.onCompleted: pushDefaultAction()

  function openSpace() {
    if (service) service.showSpace({})
  }

  // Persist the default capture mode.
  //
  // Still meaningful with no click bound to it: the keybind's chooser puts
  // this mode first and focused, and `omoide capture` with no mode argument
  // falls back to it.
  //
  // Settings live inline on this widget's entry in shell.json and the shell
  // owns that file, so writing it means handing the whole entry back through
  // updateEntryInline -- the same round trip the built-in clock uses when it
  // cycles its format. Reassigning `settings` is what makes the binding on
  // defaultAction update, so the menu's marker moves immediately.
  function setDefaultAction(action) {
    if (!action || action === root.defaultAction) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) {
      if (key !== "id") entry[key] = root.settings[key]
    }
    entry.defaultAction = action

    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Panel plumbing. The shell routes `summon` through open/close/opened, and
  // the bar coordinates popouts by object identity -- it compares its
  // activePopout against the item it loaded from the manifest, which is this
  // one. The menu used to register itself, so no comparison the bar makes ever
  // matched it: no open-panel underline, no Tab hand-off to the next panel,
  // and no clean swap when another panel took over. Everything the bar looks
  // for therefore lives here, and the menu delegates upward.
  //
  // Mirrors the surface of the shell's own Ui/Panel.qml, which is what the
  // first-party panels extend.
  function open() { menu.open() }
  function close() { menu.close() }
  function toggle() { opened ? close() : open() }
  readonly property bool opened: menu.opened

  // Set while this panel is closing to make room for another one. The panel
  // window reads it back off us to skip its fade, so the two cards swap
  // instead of cross-dissolving.
  property bool popoutSwitchClosing: false

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function () { popoutSwitchClosing = false })
  }

  // Tab from inside the menu moves to the neighbouring panel on the bar.
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root, direction)
    return false
  }

  function tooltip() {
    if (root.capturing)
      return "Omoide — pick a region, or press Esc to cancel"
    if (root.working)
      return "Omoide — enriching " + root.enriching + " capture"
           + (root.enriching === 1 ? "" : "s")
    if (root.broken)
      return "Omoide — " + root.failed + " capture"
           + (root.failed === 1 ? "" : "s") + " could not be enriched"
    var parts = []
    if (service && service.index)
      parts.push((service.index.memoryCount || 0) + " memories")
    // Today's count leads the open count when there is one, because that is
    // what the mark on the icon is reporting and the tooltip should explain it.
    if (root.dueToday > 0)
      parts.push(root.dueToday + " due today")
    if (root.todos > 0)
      parts.push(root.todos + " open to-do" + (root.todos === 1 ? "" : "s"))
    return "Omoide" + (parts.length ? " — " + parts.join(", ") : "")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A drawn mark rather than a glyph: it carries four states, needs no icon
    // font, and takes its colours from the theme.
    iconComponent: Component {
      SpaceIcon {
        anchors.centerIn: parent

        // Nudged left by most of a physical pixel, to sit on the centre.
        //
        // The mark is built from rectangles and its ancestors land on half
        // pixels -- the icon canvas sits 5.5px into a 27px slot -- so at a
        // fractional display scale the frame's two walls fall on different
        // sub-pixel phases and paint at different weights. The heavier right
        // wall is what reads as the square sitting off-centre, and measured
        // against the open-panel underline, which shares this slot's centre,
        // the mark's painted ink sat +0.88 physical px right of it.
        //
        // This is the move Ui/OpticalGlyph makes for every glyph icon in the
        // bar: offset the mark so its painted ink, rather than its layout box,
        // lands on the centre. A font exposes its ink bounds through
        // TextMetrics and a drawn mark does not, so this figure was measured
        // off a screenshot instead of derived -- in physical pixels, because
        // that is the grid the error comes from.
        //
        // layer.enabled was tried here first and is deliberately not used: it
        // evens the wall weighting out but Qt blits the layer on whole pixels,
        // which rounds this correction away.
        anchors.horizontalCenterOffset: -1.7 / dpr

        // Lifted a pixel off the canvas centre. Every icon either side of this
        // one is a font glyph, and the shell centres those on their ink rather
        // than on the canvas they sit in -- which puts them slightly above it.
        // A mark centred on the box itself therefore lands a row lower than its
        // neighbours, and the open-panel underline, pinned to the bottom of the
        // slot, turns that into visible crowding: three pixels of air under
        // this mark where every other icon has five. One pixel up puts the
        // frame in the same band the glyphs occupy.
        //
        // A nudge rather than a smaller mark: the frame's own marks are sized
        // off it, and shrinking it collapses the four corner points into each
        // other well before the frame itself looks wrong.
        // Quantising the mark's lengths rounded the frame up from 15 to 16
        // physical px, which put its bottom edge a pixel closer to the
        // underline than every neighbour. The extra fifth of a logical pixel
        // here puts the bottom back on row 22 with the rest of the row.
        anchors.verticalCenterOffset: -0.6
        iconSize: Style.bar.iconCanvas
        color: root.bar ? root.bar.foreground : Color.bar.text
        accentColor: Color.accent
        urgentColor: Color.urgent
        mode: root.iconMode
        // Lit for what today owes, not for what is on the list. A mark this
        // small carries one bit, so it goes to the question worth asking at a
        // glance: is anything due today still open.
        marked: root.dueToday > 0
      }
    }
    active: root.working || root.capturing
    tooltipText: root.tooltip()

    onPressed: function (whichButton) {
      // Middle-click is deliberately unbound: it used to open the library, and
      // a paste-adjacent button doing that by accident is worse than it not
      // working at all.
      if (whichButton === Qt.RightButton)
        root.openSpace()
      else if (whichButton === Qt.LeftButton)
        root.toggle()
    }
  }

  ActionMenu {
    id: menu
    bar: root.bar
    owner: root
    anchorItem: button
    service: root.service
    defaultAction: root.defaultAction
    onDefaultRequested: function (action) { root.setDefaultAction(action) }
  }
}
