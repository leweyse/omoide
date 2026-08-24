import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The singleton half of the plugin.
//
// Bar widgets are instantiated once per monitor, so anything that must exist
// exactly once lives here instead: the IPC surface, the timer reconciliation,
// the compose overlay, and the Space window. Widgets reach it through
// bar.shell.serviceFor("leweyse.omoide").
Item {
  id: root

  // Injected by the shell host when the plugin loads.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Bar widgets never receive `manifest`, so they cannot find the plugin's own
  // directory. Publishing it here is how they locate the CLI without a
  // hardcoded path.
  readonly property string sourceDir: (manifest && manifest.__sourceDir) || ""
  readonly property string binPath: sourceDir ? sourceDir + "/bin/omoide" : "omoide"

  // Matches the CLI: plain XDG paths under our own name. Not .local/share/omarchy,
  // which is a symlink to the read-only package tree, and not .local/state/omarchy,
  // which is Omarchy's own namespace.
  readonly property string dataHome:
    (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
    + "/omoide"
  readonly property string stateHome:
    (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/omoide"

  // Everything the bar and the Space window render comes from this cache, so
  // no QML code ever opens the database.
  property var index: ({
    version: 0, pendingCount: 0, failedCount: 0, memoryCount: 0, suggestions: [],
    digest: { events: 0, todos: 0 },
    memories: [], events: [], todos: [], collections: []
  })

  readonly property int enrichingCount: (index && index.pendingCount) || 0
  readonly property int failedCount: (index && index.failedCount) || 0
  readonly property int openTodoCount: (index && index.todos ? index.todos.length : 0)

  // No `signal indexChanged()` here: `property var index` already generates
  // one, and declaring it again is a duplicate-signal error at load time.
  signal composeRequested(var payload)
  signal spaceRequested(var payload)

  property Component cliComponent: Cli {}

  function call(args, callback) {
    return cliComponent.createObject(root, {
      command: [root.binPath].concat(args),
      callback: callback || null,
      running: true
    })
  }

  // A second capture while one is in flight cancels the first: the screenshot
  // helper opens with `pkill slurp && exit 0` so that pressing the shortcut
  // twice dismisses the picker. That makes any accidental double-invocation
  // look like "the picker closed on its own", so requests are serialised here.
  property bool capturing: false
  property string pendingMode: ""

  // Fire and forget. Use this for anything that outlives a UI interaction:
  // a tracked Process dies with its QML object, and a plugin reload destroys
  // those. call() is for short reads whose result the caller needs.
  function detach(args) {
    Quickshell.execDetached([root.binPath].concat(args))
  }

  function capture(mode) {
    if (root.capturing) return
    root.capturing = true
    root.pendingMode = mode || "screenshot"
    // The click that chose the action must be fully delivered and the menu
    // surface gone before slurp maps, or the release lands in the picker.
    captureLaunch.restart()
  }

  Timer {
    id: captureLaunch
    interval: 120
    onTriggered: {
      // Detached, NOT a tracked Process. A capture waits on an interactive
      // picker for as long as the user takes, and a tracked child dies with
      // its QML object -- which a plugin reload destroys. That killed the
      // picker mid-selection and left the screen frozen. The CLI reports back
      // over IPC when it is done, so there is nothing to track anyway.
      root.detach(["capture", root.pendingMode])
      captureCooldown.restart()
    }
  }

  // Held after launching, not cleared immediately: the capture is detached so
  // there is no exit to wait for, and a double-click on the bar icon would
  // otherwise fire two pickers. The CLI holds a lock too -- this just avoids
  // spawning a process that only exits again.
  Timer {
    id: captureCooldown
    interval: 1200
    onTriggered: root.capturing = false
  }



  function openSpace(payload) {
    root.showSpace(payload || ({}))
  }

  function refresh() {
    indexFile.reload()
  }

  // Must match INDEX_VERSION in bin/omoide.
  readonly property int indexVersion: 4
  property bool rebuildTried: false

  function applyIndex(text) {
    var parsed = null
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object")
      return

    // A plugin update can change the cache's shape. Rebuilding on a version
    // mismatch means an update self-heals instead of rendering a stale cache.
    //
    // Once only. This used to reindex on every mismatch, and since a rebuild
    // rewrites the file with the version the CLI knows, a version the shell did
    // NOT know became an endless loop: reindex, watch fires, mismatch, reindex.
    // Bumping INDEX_VERSION without touching this line was enough to trigger
    // it. Capping it at one attempt means a future skew degrades to a stale
    // cache instead of a hot loop.
    if (parsed.version !== undefined && parsed.version !== root.indexVersion) {
      if (!root.rebuildTried) {
        root.rebuildTried = true
        root.call(["reindex"], null)
        return
      }
      console.warn("omoide: index.json is v" + parsed.version + ", expected v"
                   + root.indexVersion + " -- rendering it anyway")
    }
    root.index = parsed   // emits indexChanged for anything bound to it
  }

  FileView {
    id: indexFile
    path: root.stateHome + "/index.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyIndex(text())
    onFileChanged: reload()
    onLoadFailed: root.index = ({
      version: root.indexVersion, pendingCount: 0, failedCount: 0,
      memoryCount: 0, digest: { events: 0, todos: 0 },
      memories: [], events: [], todos: [], suggestions: [], collections: [],
      alarms: []
    })
  }

  Loader {
    id: composeLoader
    active: false
    source: "surfaces/ComposeOverlay.qml"
    onLoaded: {
      item.service = root
      if (root._pendingCompose) {
        item.begin(root._pendingCompose)
        root._pendingCompose = null
      }
    }
  }

  Loader {
    id: settingsLoader
    active: false
    source: "surfaces/SettingsDialog.qml"
    onLoaded: {
      item.service = root
      item.saved.connect(function () { root.refresh() })
      if (root._pendingSettings) {
        item.open()
        root._pendingSettings = false
      }
    }
  }

  Loader {
    id: spaceWindowLoader
    active: false
    source: "surfaces/SpaceWindow.qml"
    onLoaded: {
      item.service = root
      item.show(root._pendingSpace || ({}))
      root._pendingSpace = null
    }
  }

  property var _pendingCompose: null
  property var _pendingSpace: null

  function showCompose(payload) {
    if (composeLoader.item) {
      composeLoader.item.begin(payload)
    } else {
      root._pendingCompose = payload
      composeLoader.active = true
    }
  }

  // Independent of the Space dialog: picking a model is not part of browsing
  // memories, so it does not drag Space open behind it.
  function showSettings() {
    if (settingsLoader.item) {
      settingsLoader.item.open()
    } else {
      root._pendingSettings = true
      settingsLoader.active = true
    }
  }

  property bool _pendingSettings: false

  function showSpace(payload) {
    if (spaceWindowLoader.item) {
      spaceWindowLoader.item.show(payload)
    } else {
      root._pendingSpace = payload
      spaceWindowLoader.active = true
    }
  }

  // Startup catch-up: deliver anything that came due while no shell was
  // running, and clear dead drafts. Deliberately late -- the index has to load
  // first, and nothing in it is urgent.
  Timer {
    interval: 2000
    running: true
    repeat: false
    onTriggered: root.call(["sweep"], function () { root.refresh() })
  }

  // The scheduler.
  //
  // No system timer. This service is keepLoaded, so it outlives every window
  // the plugin opens, and a notification needs the session up anyway -- there
  // is nowhere to draw a toast without one. index.json carries the pending
  // alarms and the FileView above watches it, so anything the CLI writes
  // re-arms this within the same tick.
  //
  // The wait is capped even when the next alarm is hours out, and that cap IS
  // the catch-up: a suspended laptop, a clock jump and a CLI that failed to
  // write all resolve on the next tick. None of them send a signal worth
  // waiting on.
  readonly property int alarmTickMs: 60000

  Timer {
    id: alarmTimer
    repeat: false
    onTriggered: root.armAlarms()
  }

  // `index` is a property var, so this is its generated change signal. Every
  // CLI mutation rewrites index.json, which lands here.
  onIndexChanged: root.armAlarms()

  function armAlarms() {
    var alarms = (root.index && root.index.alarms) || []
    var nowMs = Date.now()
    var soonest = -1

    for (var i = 0; i < alarms.length; i++) {
      var at = Date.parse(alarms[i].fireAt)
      if (isNaN(at))
        continue
      var wait = at - nowMs
      if (wait > 0) {
        if (soonest < 0 || wait < soonest)
          soonest = wait
        continue
      }
      // Due. Detached, and the CLI decides whether it is still owed, so a
      // repeated tick or a second shell costs a no-op rather than a second
      // toast. Firing rewrites index.json, which re-arms this from the top.
      root.detach(["reminder", "fire", "--id", alarms[i].id])
    }

    alarmTimer.interval = soonest < 0 ? root.alarmTickMs
                                      : Math.min(soonest, root.alarmTickMs)
    alarmTimer.restart()
  }

  Component.onCompleted: root.armAlarms()

  IpcHandler {
    target: "omoide"

    function capture(mode: string): string {
      root.capture(mode && mode.length ? mode : "screenshot")
      return "ok"
    }

    function compose(payloadJson: string): string {
      var payload = ({})
      try {
        payload = JSON.parse(payloadJson || "{}")
      } catch (e) {
        payload = ({})
      }
      root.showCompose(payload)
      return "ok"
    }

    function openSpace(payloadJson: string): string {
      var payload = ({})
      try {
        payload = JSON.parse(payloadJson || "{}")
      } catch (e) {
        payload = ({})
      }
      root.showSpace(payload)
      return "ok"
    }

    function closeSpace(): string {
      if (spaceWindowLoader.item)
        spaceWindowLoader.item.close()
      return "ok"
    }

    function toggleSpace(payloadJson: string): string {
      if (spaceWindowLoader.item && spaceWindowLoader.item.opened) {
        spaceWindowLoader.item.close()
        return "ok"
      }
      return openSpace(payloadJson)
    }

    function closeCompose(): string {
      if (composeLoader.item)
        composeLoader.item.dismiss()
      return "ok"
    }

    function openSettings(): string {
      root.showSettings()
      return "ok"
    }

    function refresh(): string {
      root.refresh()
      return "ok"
    }

    function state(): string {
      return JSON.stringify({
        memories: root.index.memoryCount || 0,
        enriching: root.enrichingCount,
        failed: root.failedCount,
        todos: root.openTodoCount
      })
    }

    function ping(): string {
      return "ok"
    }
  }
}
