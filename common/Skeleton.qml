import QtQuick
import qs.Commons

// A placeholder for content that is on its way: a muted block that pulses
// until the real thing replaces it. It stands in only for what is being
// fetched, never for a label or a control that is already known.
Rectangle {
  id: root

  radius: Math.max(1, Style.space(4))
  color: Color.muted
  opacity: 0.14

  SequentialAnimation on opacity {
    running: root.visible
    loops: Animation.Infinite
    NumberAnimation { to: 0.28; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.14; duration: 700; easing.type: Easing.InOutSine }
  }
}
