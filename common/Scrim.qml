import QtQuick

// The dim behind every dialog. Black at half strength, not the theme's
// menu.scrim, which is the theme background at half alpha and so lightens
// anything darker than the theme. Black darkens everywhere.
Rectangle {
  color: Qt.rgba(0, 0, 0, 0.5)
}
