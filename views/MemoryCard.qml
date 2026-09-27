import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model
import "../common/Radii.js" as Radii

// One memory in a grid: thumbnail, title, lede, then tags and open to-dos.
//
// Its own file because two grids show it, the Library and a collection, and a
// second copy would drift the moment either changed. `activated` rather than
// a direct call, so the card does not need to know which page owns it.
BorderSurface {
  id: card

  property var memory: ({})
  // Keyboard focus, set by the grid from its cursor.
  property bool hasCursor: false
  signal activated()

  // Insets for everything but the thumbnail, which deliberately bleeds to the
  // edges.
  //
  // Wider than it is tall. Across, less than xxl reads as text pressed against
  // the frame. Down, more only adds slack above the title and under the last
  // tag, because the rows already carry their own spacing.
  readonly property real padX: Style.spacing.xxl
  readonly property real padY: Style.spacing.lg

  width: parent ? parent.width : 0
  height: cardLayout.implicitHeight + card.borderTop + card.borderBottom
  radius: Style.cornerRadius
  color: Color.popups.background
  // At rest, the outline-button border, not popups.border: that token defaults
  // to the ACCENT, which would make the accent focus border indistinguishable.
  // The width is the same 2px in BOTH states. A card measures its height as
  // content plus border widths, so a thicker focus border would resize the card
  // and reflow the grid on every arrow key.
  borderSpec: card.hasCursor
              ? Border.flat(Color.accent, Math.max(1, Style.space(2)))
              : Border.withWidth(
                  Border.controlSpec("normal", Color.popups.text, Color.accent),
                  Math.max(1, Style.space(2)))
  clip: true

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: card.activated()
  }

  FocusRing {
    anchors.fill: parent
    radius: card.radius
    cornersOnly: true
    hostBorder: Math.max(1, Style.space(2))
    hasCursor: card.hasCursor
    // twoTone matters only for the full ring; the marks carry their own
    // halo, which is the same guarantee against arbitrary thumbnails.
    twoTone: true
    hot: hoverArea.containsMouse
  }

  Column {
    id: cardLayout
    // Anchored inside the frame so no child can paint over the border.
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: card.borderLeft
    anchors.rightMargin: card.borderRight
    anchors.topMargin: card.borderTop
    spacing: 0

    // Only the top corners: the thumbnail bleeds to the card's top edge
    // and the text continues below it. Radius less the border it sits
    // behind, so the inner curve matches the outer one.
    RoundedImage {
      width: parent.width
      // The capture's own shape, not a fixed ratio, so a wide selection and a
      // tall one look different in the grid.
      //
      // Bounded, unlike the detail page: this is a browsing surface, and
      // one panorama or one very tall capture should not own a column.
      // Roughly 3:1 through 4:5 passes through untouched; beyond that the
      // card crops and the detail page shows the full shape.
      height: card.memory.thumb
              ? Math.round(Math.max(width * 0.34,
                  Math.min(width * 1.25,
                    width / (card.memory.aspect > 0 ? card.memory.aspect : 1.6))))
              : 0
      visible: !!card.memory.thumb
      source: card.memory.thumb ? "file://" + card.memory.thumb : ""
      fillMode: Image.PreserveAspectCrop
      borderWidth: 0
      topLeftRadius: Radii.nested(Style.cornerRadius, card.borderLeft)
      topRightRadius: Radii.nested(Style.cornerRadius, card.borderRight)
      bottomLeftRadius: 0
      bottomRightRadius: 0
    }

    // A padded region rather than a bare Column: this is what gives the
    // text equal breathing room on all four sides, including under the
    // last row, which a Column with only an x offset cannot do.
    //
    // Painted rather than transparent, in the card's own colour, so it covers
    // the border's inner edge exactly as the thumbnail above it does.
    //
    // A stroked Rectangle antialiases its inner edge a fraction of a pixel into
    // the content area. The opaque thumbnail paints over that bleed; a
    // transparent text region would not, and the text half of the card would
    // read as having a second, heavier frame.
    //
    // Bottom corners only. This is the last thing in the column, so it meets
    // the card's rounded bottom; square corners here would paint over that
    // curve, the card's `clip` being rectangular and unable to trim them.
    Rectangle {
      width: parent.width
      implicitHeight: textColumn.implicitHeight + card.padY * 2
      height: implicitHeight
      color: Color.popups.background
      topLeftRadius: 0
      topRightRadius: 0
      bottomLeftRadius: Radii.nested(Style.cornerRadius, card.borderLeft)
      bottomRightRadius: Radii.nested(Style.cornerRadius, card.borderRight)

      Column {
        id: textColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.padX
        anchors.rightMargin: card.padX
        anchors.topMargin: card.padY
        spacing: Style.spacing.sm

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: Model.truncate(card.memory.title, 80)
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          lineHeight: 1.15
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.subtitle
        }

        Text {
          visible: !!card.memory.lede
          width: parent.width
          textFormat: Text.PlainText
          text: Model.truncate(card.memory.lede, 110)
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
        }

        Item {
          width: parent.width
          height: metaRow.visible ? metaRow.implicitHeight + Style.spacing.sm : 0

          // Anchored to both sides, not just the bottom. At its natural width
          // the row is as wide as its text, and a long tag would run under the
          // card's border and be clipped mid-word.
          Row {
            id: metaRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Style.spacing.md
            visible: (card.memory.tags || []).length > 0
                     || card.memory.openTodos > 0

            Text {
              id: todoCount
              visible: card.memory.openTodos > 0
              text: "○ " + card.memory.openTodos
              color: Color.accent
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.body
            }

            Text {
              // Whatever the count leaves. A Row hands each child its implicit
              // width, so the elide below only bites once this is told how much
              // room it actually has. The count is the only thing ahead of it, so
              // the arithmetic stays honest without a Layout.
              width: metaRow.width
                     - (todoCount.visible ? todoCount.width + metaRow.spacing : 0)
              textFormat: Text.PlainText
              // Three tags is a cap, not a width. Two long ones overflow where
              // four short ones fit, so the elide still applies.
              text: (card.memory.tags || []).slice(0, 3).join(" · ")
              elide: Text.ElideRight
              color: Color.muted
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }
}
