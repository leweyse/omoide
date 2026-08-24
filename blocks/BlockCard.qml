import QtQuick
import qs.Commons
import qs.Ui
import "../common"

BorderSurface {
  id: root
  // Which row this card is drawing. Every block has them, so they live here
  // rather than being threaded through the ones that happen to be editable.
  property string blockId: ""
  property string blockType: ""
  // Keyboard cursor. Every card takes it, including the ones Enter does nothing
  // on: arrows walking card to card is how this page scrolls, so skipping an
  // inert card would leave a hole in the scroll path.
  property bool hasCursor: false

  property alias heading: label.text
  default property alias body: holder.data

  // A control pinned to the card's top-right corner -- an edit affordance, say.
  // It lives here rather than in the card's content because `body` is the
  // default property, so anything a caller declares lands inside the padded
  // column and cannot reach the corner.
  property Component trailing: null

  // One token for the inset, so the card's height and its content's margins
  // cannot drift apart. This was md (6px), which left text almost touching
  // the border on every block in the page.
  readonly property int pad: Style.spacing.xxl

  width: parent ? parent.width : 0
  height: layout.implicitHeight + root.pad * 2
  radius: Style.cornerRadius
  color: Color.popups.background
  // The outline-button border, not popups.border -- that token defaults to
  // the ACCENT, so an accent focus ring was invisible against every unfocused
  // card beside it. Same width, so nothing reflows.
  // Accent on focus. The width does NOT change -- a card measures its height
  // as content plus border widths, so a thicker focus border would resize the
  // card and reflow the grid on every arrow key.
  borderSpec: root.hasCursor
              ? Border.flat(Color.accent, 1)
              : Border.controlSpec("normal", Color.popups.text, Color.accent)

  FocusRing {
    anchors.fill: parent
    radius: root.radius
    hasCursor: root.hasCursor
    hot: false
  }

  Column {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.pad
    // Keeps the content clear of the corner control when there is one.
    anchors.rightMargin: root.pad
                         + (trailingSlot.item ? trailingSlot.width + Style.spacing.md : 0)
    // Heading to content. The same 12px every card's sections use, so a label
    // sits off its content by the same amount everywhere.
    spacing: Style.spacing.xxl

    PanelSectionHeader {
      id: label
      visible: text.length > 0
      // A list block's heading is the model's own words, so it is untrusted and
      // must not be sniffed for markup. PanelSectionHeader is a Text, so this
      // overrides its AutoText default from out here.
      textFormat: Text.PlainText
      // popups.text rather than muted: PanelSectionHeader darkens whatever it
      // is given by 1.4, so handing it an already-dim colour rendered the
      // label twice-faded. One step up in size too -- at caption (10px) a
      // bold label under 12px body text was the smallest thing on the page.
      foreground: Color.popups.text
      fontSize: Style.font.bodySmall
      fontFamily: Style.font.resolvedFamily
    }

    Item {
      id: holder
      width: parent.width
      implicitHeight: childrenRect.height
      height: childrenRect.height
    }
  }

  Loader {
    id: trailingSlot
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.pad
    anchors.rightMargin: root.pad
    sourceComponent: root.trailing
  }
}
