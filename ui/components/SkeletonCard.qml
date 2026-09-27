import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../common/Radii.js" as Radii

// A memory card still loading, drawn to MemoryCard's measurements: the same
// frame, the same thumbnail bounds, the same text insets and line sizes. The
// grid places it where a card will land, so the real one replaces it without
// the columns shifting around it.
BorderSurface {
  id: card

  // The shape to hold room for; the grid hands one in.
  property real aspect: 1.6

  readonly property real padX: Style.spacing.xxl
  readonly property real padY: Style.spacing.lg

  width: parent ? parent.width : 0
  height: body.implicitHeight + card.borderTop + card.borderBottom
  radius: Style.cornerRadius
  color: Color.popups.background
  borderSpec: Border.withWidth(
                Border.controlSpec("normal", Color.popups.text, Color.accent),
                Math.max(1, Style.space(2)))
  clip: true

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: card.borderLeft
    anchors.rightMargin: card.borderRight
    anchors.topMargin: card.borderTop

    // MemoryCard's thumbnail bounds, so the placeholder is as tall as the
    // card that replaces it.
    Skeleton {
      width: parent.width
      height: Math.round(Math.max(width * 0.34, Math.min(width * 1.25, width / card.aspect)))
      radius: 0
      topLeftRadius: Radii.nested(Style.cornerRadius, card.borderLeft)
      topRightRadius: Radii.nested(Style.cornerRadius, card.borderRight)
    }

    Item {
      width: parent.width
      height: lines.implicitHeight + card.padY * 2

      Column {
        id: lines
        x: card.padX
        y: card.padY
        width: parent.width - card.padX * 2
        spacing: Style.spacing.sm

        Skeleton { width: parent.width * 0.8; height: Math.round(Style.font.subtitle * 1.15) }
        Skeleton { width: parent.width * 0.6; height: Style.font.body }
        Skeleton { width: parent.width * 0.4; height: Style.font.body }
      }
    }
  }
}
