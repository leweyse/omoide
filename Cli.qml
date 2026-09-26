import QtQuick
import Quickshell.Io

// One invocation of the CLI (cli/). Created on demand by Service.call()
// and destroyed when it exits, so a slow capture never blocks the shell.
Process {
  id: proc

  property var callback: null
  property bool destroyOnExit: true

  stdout: StdioCollector { id: out; waitForEnd: true }
  stderr: StdioCollector { id: err; waitForEnd: true }

  onExited: function (exitCode) {
    if (proc.callback) {
      var parsed = null
      try {
        parsed = JSON.parse(out.text)
      } catch (e) {
        parsed = null
      }
      // Raw stdout as a fourth argument: not every caller speaks JSON --
      // the chooser reads a menu selection, which is a bare label.
      proc.callback(exitCode, parsed, String(err.text || ""), String(out.text || ""))
    }
    if (proc.destroyOnExit)
      Qt.callLater(function () { proc.destroy() })
  }
}
