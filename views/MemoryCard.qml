import QtQuick
import qs.Commons
import qs.Ui
import ".." as Root
import "../MemoryModel.js" as Model

// One memory in a grid: thumbnail, title, lede, then tags and open to-dos.
//
// Its own file because two grids show it -- the Library and a collection -- and
// a second copy would drift the moment either changed. `activated` rather than
// a direct call, so the card does not need to know which page owns it.
BorderSurface {
  id: card

  property var memory: ({})
  signal activated()

  // One inset for the whole card. The thumbnail deliberately bleeds to the
  // edges; everything else sits inside this.
  readonly property real pad: Style.spacing.md

  width: parent ? parent.width : 0
  height: cardLayout.implicitHeight + card.borderTop + card.borderBottom
  radius: Style.cornerRadius
  color: Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
  clip: true

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: card.activated()
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
    Root.RoundedImage {
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
        spacing: Style.spacing.xs

        Text {
          width: parent.width
          text: Model.truncate(card.memory.title, 80)
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          lineHeight: 1.15
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
        }

        Text {
          visible: !!card.memory.lede
          width: parent.width
          text: Model.truncate(card.memory.lede, 110)
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          width: parent.width
          height: metaRow.visible ? metaRow.implicitHeight + Style.spacing.xs : 0

          Row {
            id: metaRow
            anchors.bottom: parent.bottom
            spacing: Style.spacing.sm
            visible: (card.memory.tags || []).length > 0
                     || card.memory.openTodos > 0

            Text {
              visible: card.memory.openTodos > 0
              text: "○ " + card.memory.openTodos
              color: Color.accent
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              text: (card.memory.tags || []).slice(0, 3).join(" · ")
              color: Color.muted
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
