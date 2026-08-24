import QtQuick

// The dim behind every dialog. Black at half strength, not the theme's
// menu.scrim: that token is the theme background at 50% alpha, which LIGHTENS
// anything darker than the theme -- a dialog over a near-black page sat in a
// grey haze instead of a dim. Black darkens everywhere.
Rectangle {
  color: Qt.rgba(0, 0, 0, 0.5)
}
