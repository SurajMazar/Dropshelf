import AppKit

protocol ShelfItemCellDelegate: AnyObject {
    func shelfItemCellDidRequestRemove(_ cell: ShelfItemCell)
    func shelfItemCellDidRequestReveal(_ cell: ShelfItemCell)
    func shelfItemCellDidRequestQuickLook(_ cell: ShelfItemCell)
    func shelfItemCellDidRequestCopyPath(_ cell: ShelfItemCell)
}

final class ShelfItemCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShelfItemCell")

    weak var cellDelegate: ShelfItemCellDelegate?

    private let iconContainer = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private var trackingArea: NSTrackingArea?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 92))
        root.wantsLayer = true
        root.layer?.cornerRadius = 8

        iconContainer.frame = NSRect(x: 6, y: 26, width: 64, height: 64)
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 8
        iconContainer.layer?.shadowColor = NSColor.black.cgColor
        iconContainer.layer?.shadowOpacity = 0.25
        iconContainer.layer?.shadowOffset = CGSize(width: 0, height: -1)
        iconContainer.layer?.shadowRadius = 3
        iconContainer.layer?.masksToBounds = false
        root.addSubview(iconContainer)

        iconView.frame = iconContainer.bounds
        iconView.autoresizingMask = [.width, .height]
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconContainer.addSubview(iconView)

        nameLabel.frame = NSRect(x: 2, y: 4, width: 72, height: 18)
        nameLabel.font = .systemFont(ofSize: 10, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textColor = .labelColor
        nameLabel.maximumNumberOfLines = 1
        root.addSubview(nameLabel)

        removeButton.frame = NSRect(x: 54, y: 74, width: 18, height: 18)
        removeButton.bezelStyle = .circular
        removeButton.isBordered = false
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(handleRemove)
        removeButton.isHidden = true
        removeButton.toolTip = "Remove from shelf"
        root.addSubview(removeButton)

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let menu = NSMenu()
        menu.addItem(withTitle: "Quick Look", action: #selector(handleQuickLook), keyEquivalent: " ")
            .target = self
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(handleReveal), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Copy Path", action: #selector(handleCopyPath), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove", action: #selector(handleRemove), keyEquivalent: "")
            .target = self
        view.menu = menu
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let existing = trackingArea {
            view.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        removeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        removeButton.isHidden = true
    }

    func configure(with item: ShelfItem) {
        iconView.image = item.icon
        nameLabel.stringValue = item.displayName
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        view.layer?.backgroundColor = (isSelected || highlightState == .forSelection)
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
    }

    @objc private func handleRemove() { cellDelegate?.shelfItemCellDidRequestRemove(self) }
    @objc private func handleReveal() { cellDelegate?.shelfItemCellDidRequestReveal(self) }
    @objc private func handleQuickLook() { cellDelegate?.shelfItemCellDidRequestQuickLook(self) }
    @objc private func handleCopyPath() { cellDelegate?.shelfItemCellDidRequestCopyPath(self) }
}
