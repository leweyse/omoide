import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "dialogs"

// One icon. Left-click toggles the action menu, right-click opens the library.
//
// No click captures directly. A capture grabs the pointer for a region pick,
// so a misclick on the bar must not start one; the menu names every mode, and a
// capture is always chosen rather than triggered.
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
  // updateEntryInline, the same round trip the built-in clock makes when it
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
  // the bar coordinates popouts by object identity: it compares activePopout
  // against the item it loaded from the manifest, which is this one. So
  // everything the bar looks for lives here and the menu delegates upward; a
  // menu that registered itself would get no open-panel underline, no Tab
  // hand-off, and no clean swap when another panel takes over.
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

        // Optical centring, in physical pixels. The icon canvas sits on a half
        // pixel, so at a fractional scale the frame's walls paint at different
        // weights and the ink reads right of centre. Ui/OpticalGlyph makes the
        // same correction for glyph icons from TextMetrics; a drawn mark has no
        // ink bounds, so this figure is measured off a screenshot.
        //
        // Not layer.enabled: Qt blits a layer on whole pixels, which rounds
        // this correction away.
        anchors.horizontalCenterOffset: -1.7 / dpr

        // Lifted to the band the neighbouring glyph icons occupy: the shell
        // centres a glyph on its ink, which sits above the canvas centre, and
        // the open-panel underline makes a lower mark look crowded. Measured,
        // so the bottom edge lands on the same physical row as its neighbours.
        // A nudge rather than a smaller mark, because the frame's corner
        // points are sized off it and collide when it shrinks.
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
      // Middle-click is deliberately unbound. It is the paste button, and
      // opening the library by accident is worse than no action at all.
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
