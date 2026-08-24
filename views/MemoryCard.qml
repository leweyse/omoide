import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model

// One memory in a grid: thumbnail, title, lede, then tags and open to-dos.
//
// Its own file because two grids show it -- the Library and a collection -- and
// a second copy would drift the moment either changed. `activated` rather than
// a direct call, so the card does not need to know which page owns it.
BorderSurface {
  id: card

  property var memory: ({})
  // Keyboard focus, set by the grid from its cursor.
  property bool hasCursor: false
  signal activated()

  // One inset for the whole card. The thumbnail deliberately bleeds to the
  // edges; everything else sits inside this.
  readonly property real pad: Style.spacing.lg

  width: parent ? parent.width : 0
  height: cardLayout.implicitHeight + card.borderTop + card.borderBottom
  radius: Style.cornerRadius
  color: Color.popups.background
  // The outline-button border, not popups.border -- that token defaults to
  // the ACCENT, so an accent focus ring on a card was invisible against every
  // unfocused card beside it. Same width, so nothing reflows.
  // Accent on focus. The width does NOT change -- a card measures its height
  // as content plus border widths, so a thicker focus border would resize the
  // card and reflow the grid on every arrow key. 2px in BOTH states, matching
  // the dialog chrome and the image frame, which is what keeps that rule.
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
      // The capture's own shape, not a fixed ratio. A fixed 0.62 cropped
      // every thumbnail to the same rectangle, so a wide selection and a
      // tall one looked identical in the grid.
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
      topLeftRadius: Math.max(0, Style.cornerRadius - card.borderLeft)
      topRightRadius: Math.max(0, Style.cornerRadius - card.borderRight)
      bottomLeftRadius: 0
      bottomRightRadius: 0
    }

    // A padded region rather than a bare Column: this is what gives the
    // text equal breathing room on all four sides, including under the
    // last row, which a Column with only an x offset cannot do.
    Item {
      width: parent.width
      implicitHeight: textColumn.implicitHeight + card.pad * 2
      height: implicitHeight

      Column {
        id: textColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.pad
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

          Row {
            id: metaRow
            anchors.bottom: parent.bottom
            spacing: Style.spacing.md
            visible: (card.memory.tags || []).length > 0
                     || card.memory.openTodos > 0

            Text {
              visible: card.memory.openTodos > 0
              text: "○ " + card.memory.openTodos
              color: Color.accent
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.body
            }

            Text {
              textFormat: Text.PlainText
              text: (card.memory.tags || []).slice(0, 3).join(" · ")
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
