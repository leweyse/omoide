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

  // A control pinned to the card's top-right corner, such as an edit button.
  // It lives here rather than in the content because `body` is the default
  // property: anything a caller declares lands inside the padded column and
  // cannot reach the corner.
  property Component trailing: null

  // One token for the inset, so the card's height and its content's margins
  // cannot drift apart.
  readonly property int pad: Style.spacing.xxxl

  width: parent ? parent.width : 0
  height: layout.implicitHeight + root.pad * 2
  radius: Style.cornerRadius
  color: Color.popups.background
  // The outline-button border, not popups.border: that token defaults to the
  // accent, so a focused card would look like every other card. Focus keeps
  // the same width, because a card's height includes its border and a thicker
  // one would reflow the grid on every arrow key.
  borderSpec: root.hasCursor
              ? Border.flat(Color.accent, 1)
              : Border.controlSpec("normal", Color.popups.text, Color.accent)

  FocusRing {
    anchors.fill: parent
    radius: root.radius
    cornersOnly: true
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
                         + (trailingSlot.item ? trailingSlot.width + Style.spacing.lg : 0)
    // Heading to content, the gap every card's sections use, so a label sits
    // off its content by the same amount everywhere.
    spacing: Style.spacing.xxxl

    PanelSectionHeader {
      id: label
      visible: text.length > 0
      // A list block's heading is the model's own words, so it is untrusted and
      // must not be sniffed for markup. PanelSectionHeader is a Text, so this
      // overrides its AutoText default from out here.
      textFormat: Text.PlainText
      // popups.text rather than muted: PanelSectionHeader darkens whatever it
      // is given, so an already-dim colour would render twice-faded. Body size,
      // so the label is not smaller than the text it heads.
      foreground: Color.popups.text
      fontSize: Style.font.body
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
