import AppKit
import Quartz

final class ShelfDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onCommandF: (() -> Void)?
    var onEscape: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            onCommandF?()
            return true
        }
        if event.keyCode == 53 { // Escape
            if let onEscape {
                onEscape()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class PassThroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }
}

final class DraggableHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class DockedTabView: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?

    private let iconView = NSImageView()
    private let badgeBg = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var hoverTask: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHidden else { return }
        hoverTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.onHover?() }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    override func mouseExited(with event: NSEvent) {
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func setupSubviews() {
        wantsLayer = true

        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: "Shelf")?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = .labelColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)

        badgeBg.wantsLayer = true
        badgeBg.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeBg.isHidden = true
        addSubview(badgeBg)

        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.isHidden = true
        addSubview(badgeLabel)
    }

    func update(count: Int) {
        if count > 0 {
            badgeLabel.stringValue = count > 99 ? "99+" : "\(count)"
            badgeBg.isHidden = false
            badgeLabel.isHidden = false
        } else {
            badgeBg.isHidden = true
            badgeLabel.isHidden = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let iconSize: CGFloat = min(28, max(18, bounds.width * 0.6))
        iconView.frame = NSRect(
            x: (bounds.width - iconSize) / 2,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )

        let text = badgeLabel.stringValue.isEmpty ? "0" : badgeLabel.stringValue
        let textWidth = (text as NSString).size(withAttributes: [.font: badgeLabel.font as Any]).width
        let badgeH: CGFloat = 16
        let badgeW = max(badgeH, ceil(textWidth) + 8)
        let badgeX = min(bounds.width - badgeW - 2, iconView.frame.maxX - 6)
        let badgeY = iconView.frame.maxY - badgeH / 2
        badgeBg.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        badgeBg.layer?.cornerRadius = badgeH / 2
        badgeLabel.frame = badgeBg.frame
    }

    override var mouseDownCanMoveWindow: Bool { false }

    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onClick?() }
        didDrag = false
    }
}

final class ShelfViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate, ShelfItemCellDelegate, NSSearchFieldDelegate {
    private let store: ShelfStore
    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var emptyLabel: NSTextField!
    private var countLabel: NSTextField!
    private var headerView: NSView!
    private var separatorView: NSBox!
    private var dockedView: DockedTabView!
    private var dockButton: NSButton!
    private var searchBarView: NSView!
    private var searchField: NSSearchField!
    private var filterPopup: NSPopUpButton!
    private var isSearching = false
    private var previewPanelItems: [URL] = []

    var onDockToggle: (() -> Void)?
    var onUndockRequested: (() -> Void)?

    private static let panelSize = NSSize(width: 360, height: 180)
    private static let headerHeight: CGFloat = 36
    private static let searchBarHeight: CGFloat = 32

    init(store: ShelfStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = ShelfDropView(frame: NSRect(origin: .zero, size: Self.panelSize))
        container.wantsLayer = true
        container.registerForDraggedTypes([.fileURL])
        container.onDrop = { [weak self] urls in
            self?.store.addAll(urls: urls)
        }
        container.onCommandF = { [weak self] in self?.toggleSearch() }
        container.onEscape = { [weak self] in
            guard let self else { return }
            if self.isSearching {
                self.hideSearch()
            } else {
                self.view.window?.orderOut(nil)
            }
        }

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        container.addSubview(effect)

        headerView = buildHeader(containerWidth: container.bounds.width)
        container.addSubview(headerView)

        separatorView = NSBox()
        separatorView.boxType = .separator
        separatorView.frame = NSRect(
            x: 12,
            y: container.bounds.height - Self.headerHeight,
            width: container.bounds.width - 24,
            height: 1
        )
        separatorView.autoresizingMask = [.width, .minYMargin]
        separatorView.alphaValue = 0.4
        container.addSubview(separatorView)

        emptyLabel = PassThroughTextField(labelWithString: "Drop files here")
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        let emptyLabelHeight: CGFloat = 20
        let emptyArea = container.bounds.height - Self.headerHeight
        emptyLabel.frame = NSRect(
            x: 0,
            y: (emptyArea - emptyLabelHeight) / 2,
            width: container.bounds.width,
            height: emptyLabelHeight
        )
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        container.addSubview(emptyLabel)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 76, height: 92)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        layout.scrollDirection = .horizontal

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ShelfItemCell.self, forItemWithIdentifier: ShelfItemCell.identifier)
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView = NSScrollView(frame: NSRect(
            x: 0,
            y: 0,
            width: container.bounds.width,
            height: container.bounds.height - Self.headerHeight
        ))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.horizontalScroller?.alphaValue = 0.5
        container.addSubview(scrollView)

        searchBarView = buildSearchBar(containerWidth: container.bounds.width)
        searchBarView.isHidden = true
        container.addSubview(searchBarView)

        dockedView = buildDockedView(containerBounds: container.bounds)
        dockedView.isHidden = true
        container.addSubview(dockedView)

        self.view = container

        store.onChange = { [weak self] in
            self?.reload()
        }
        reload()
    }

    private func buildDockedView(containerBounds: NSRect) -> DockedTabView {
        let v = DockedTabView(frame: containerBounds)
        v.autoresizingMask = [.width, .height]
        v.onClick = { [weak self] in self?.onUndockRequested?() }
        v.onHover = { [weak self] in self?.onUndockRequested?() }
        return v
    }

    func setDocked(_ docked: Bool) {
        headerView.isHidden = docked
        separatorView.isHidden = docked
        scrollView.isHidden = docked
        emptyLabel.isHidden = docked || !store.items.isEmpty
        dockedView.isHidden = !docked
        if docked {
            updateDockedBadge()
        }
        updateDockButtonIcon()
    }

    private func updateDockedBadge() {
        dockedView?.update(count: store.items.count)
    }

    private func updateDockButtonIcon() {
        let docked = !dockedView.isHidden
        let name = docked ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        dockButton?.image = NSImage(systemSymbolName: name, accessibilityDescription: docked ? "Expand" : "Collapse")
    }

    private func buildHeader(containerWidth: CGFloat) -> NSView {
        let header = DraggableHeaderView(frame: NSRect(
            x: 0,
            y: Self.panelSize.height - Self.headerHeight,
            width: containerWidth,
            height: Self.headerHeight
        ))
        header.autoresizingMask = [.width, .minYMargin]

        countLabel = PassThroughTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        countLabel.textColor = .labelColor
        countLabel.frame = NSRect(x: 14, y: 10, width: 120, height: 16)
        header.addSubview(countLabel)

        let buttonSize: CGFloat = 22
        let spacing: CGFloat = 2
        let symbols: [(symbol: String, action: Selector, tip: String, tint: NSColor)] = [
            ("magnifyingglass", #selector(toggleSearch), "Search (⌘F)", .systemOrange),
            ("arrow.down.right.and.arrow.up.left", #selector(toggleDock), "Collapse", .systemPurple),
            ("arrow.up.forward.app", #selector(revealAll), "Reveal in Finder", .systemBlue),
            ("trash", #selector(clearAll), "Clear all", .systemRed),
            ("xmark", #selector(hideShelf), "Close shelf", .secondaryLabelColor),
        ]

        var x = containerWidth - 8 - buttonSize
        for item in symbols.reversed() {
            let btn = NSButton()
            btn.frame = NSRect(x: x, y: 7, width: buttonSize, height: buttonSize)
            btn.autoresizingMask = [.minXMargin]
            btn.isBordered = false
            btn.bezelStyle = .circular
            btn.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.tip)
            btn.contentTintColor = item.tint
            btn.imageScaling = .scaleProportionallyDown
            btn.target = self
            btn.action = item.action
            btn.toolTip = item.tip
            header.addSubview(btn)
            if item.symbol == "sidebar.squares.right" { dockButton = btn }
            x -= buttonSize + spacing
        }

        return header
    }

    @objc private func toggleDock() {
        onDockToggle?()
    }

    // MARK: - Search bar

    private func buildSearchBar(containerWidth: CGFloat) -> NSView {
        let barY = Self.panelSize.height - Self.headerHeight - Self.searchBarHeight
        let bar = NSView(frame: NSRect(x: 0, y: barY, width: containerWidth, height: Self.searchBarHeight))
        bar.autoresizingMask = [.width, .minYMargin]

        let fieldH: CGFloat = 22
        let fieldY = (Self.searchBarHeight - fieldH) / 2
        let popupW: CGFloat = 96
        let sidePad: CGFloat = 10
        let interPad: CGFloat = 6

        searchField = NSSearchField()
        searchField.frame = NSRect(x: sidePad, y: fieldY,
                                   width: containerWidth - popupW - sidePad * 2 - interPad,
                                   height: fieldH)
        searchField.autoresizingMask = [.width]
        searchField.placeholderString = "Search"
        searchField.font = .systemFont(ofSize: 12)
        searchField.delegate = self
        bar.addSubview(searchField)

        filterPopup = NSPopUpButton(frame: NSRect(
            x: containerWidth - popupW - sidePad,
            y: fieldY,
            width: popupW,
            height: fieldH
        ), pullsDown: false)
        filterPopup.autoresizingMask = [.minXMargin]
        filterPopup.font = .systemFont(ofSize: 11)
        filterPopup.target = self
        filterPopup.action = #selector(filterChanged(_:))
        populateFilterPopup()
        bar.addSubview(filterPopup)

        return bar
    }

    private func populateFilterPopup() {
        let counts = store.typeCounts
        let previousIndex = filterPopup.indexOfSelectedItem
        filterPopup.removeAllItems()
        for type in FileTypeFilter.allCases {
            let count = counts[type] ?? 0
            let title: String
            if type == .all {
                title = "All (\(store.items.count))"
            } else {
                title = count > 0 ? "\(type.rawValue) (\(count))" : type.rawValue
            }
            filterPopup.addItem(withTitle: title)
        }
        let restoreIndex = (0..<FileTypeFilter.allCases.count).contains(previousIndex) ? previousIndex : 0
        filterPopup.selectItem(at: restoreIndex)
    }

    @objc private func filterChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < FileTypeFilter.allCases.count else { return }
        store.typeFilter = FileTypeFilter.allCases[idx]
    }

    @objc private func toggleSearch() {
        isSearching ? hideSearch() : showSearch()
    }

    private func showSearch() {
        guard !isSearching else { return }
        isSearching = true
        searchBarView.isHidden = false
        populateFilterPopup()

        let newHeight = Self.panelSize.height - Self.headerHeight - Self.searchBarHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            scrollView.animator().setFrameSize(NSSize(width: scrollView.frame.width, height: newHeight))
            emptyLabel.animator().frame = NSRect(
                x: 0,
                y: (newHeight - 20) / 2,
                width: view.bounds.width,
                height: 20
            )
        }
        view.window?.makeFirstResponder(searchField)
    }

    @objc private func hideSearch() {
        guard isSearching else { return }
        isSearching = false
        searchField.stringValue = ""
        store.searchQuery = ""
        store.typeFilter = .all
        filterPopup.selectItem(at: 0)
        searchBarView.isHidden = true

        let newHeight = Self.panelSize.height - Self.headerHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            scrollView.animator().setFrameSize(NSSize(width: scrollView.frame.width, height: newHeight))
            emptyLabel.animator().frame = NSRect(
                x: 0,
                y: (newHeight - 20) / 2,
                width: view.bounds.width,
                height: 20
            )
        }
    }

    // NSSearchFieldDelegate / NSControlTextEditingDelegate
    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as AnyObject?) === searchField else { return }
        store.searchQuery = searchField.stringValue
    }

    private func reload() {
        collectionView.reloadData()
        let total = store.items.count
        let filtered = store.filteredItems.count
        let isDocked = !(dockedView?.isHidden ?? true)

        if total == 0 {
            emptyLabel.stringValue = "Drop files here"
        } else if filtered == 0 {
            emptyLabel.stringValue = "No matches"
        }
        emptyLabel.isHidden = filtered > 0 || isDocked

        if total == 0 {
            countLabel.stringValue = ""
        } else if filtered == total {
            countLabel.stringValue = total == 1 ? "1 item" : "\(total) items"
        } else {
            countLabel.stringValue = "\(filtered) of \(total)"
        }

        if filterPopup != nil { populateFilterPopup() }
        updateDockedBadge()
    }

    // MARK: - Header actions

    @objc private func clearAll() { store.clear() }

    @objc private func hideShelf() {
        view.window?.orderOut(nil)
    }

    @objc private func revealAll() {
        let urls = store.items.map { $0.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: - Data source

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        store.filteredItems.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: ShelfItemCell.identifier, for: indexPath) as! ShelfItemCell
        let items = store.filteredItems
        if indexPath.item < items.count {
            cell.configure(with: items[indexPath.item])
        }
        cell.cellDelegate = self
        return cell
    }

    // MARK: - Drag IN

    func collectionView(_ collectionView: NSCollectionView,
                        validateDrop draggingInfo: any NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        if draggingInfo.draggingSource as AnyObject? === collectionView { return [] }
        guard draggingInfo.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
        dropOperation.pointee = .before
        return .copy
    }

    func collectionView(_ collectionView: NSCollectionView,
                        acceptDrop draggingInfo: any NSDraggingInfo,
                        indexPath: IndexPath,
                        dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let urls = draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else { return false }
        store.addAll(urls: urls)
        return true
    }

    // MARK: - Drag OUT

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        let items = store.filteredItems
        guard indexPath.item < items.count else { return nil }
        return items[indexPath.item].url as NSURL
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint,
                        forItemsAt indexPaths: Set<IndexPath>) {
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint,
                        dragOperation operation: NSDragOperation) {
        // Keep items on shelf after drag-out (copy semantics).
    }

    // MARK: - Quick Look

    override func keyDown(with event: NSEvent) {
        let spaceKey: UInt16 = 49
        let deleteKey: UInt16 = 51
        if event.keyCode == spaceKey, !collectionView.selectionIndexPaths.isEmpty {
            toggleQuickLook()
        } else if event.keyCode == deleteKey {
            removeSelectedItems()
        } else {
            super.keyDown(with: event)
        }
    }

    private func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func removeSelectedItems() {
        let items = store.filteredItems
        let ids = collectionView.selectionIndexPaths.compactMap { idx -> UUID? in
            guard idx.item < items.count else { return nil }
            return items[idx.item].id
        }
        for id in ids { store.remove(id: id) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        let items = store.filteredItems
        previewPanelItems = collectionView.selectionIndexPaths
            .sorted()
            .compactMap { idx in idx.item < items.count ? items[idx.item].url : nil }
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
        previewPanelItems = []
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { previewPanelItems.count }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        previewPanelItems[index] as NSURL
    }

    // MARK: - ShelfItemCellDelegate

    private func item(for cell: ShelfItemCell) -> ShelfItem? {
        guard let indexPath = collectionView.indexPath(for: cell) else { return nil }
        let items = store.filteredItems
        guard indexPath.item < items.count else { return nil }
        return items[indexPath.item]
    }

    func shelfItemCellDidRequestRemove(_ cell: ShelfItemCell) {
        guard let item = item(for: cell) else { return }
        store.remove(id: item.id)
    }

    func shelfItemCellDidRequestReveal(_ cell: ShelfItemCell) {
        guard let item = item(for: cell) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func shelfItemCellDidRequestQuickLook(_ cell: ShelfItemCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        collectionView.selectionIndexPaths = [indexPath]
        toggleQuickLook()
    }

    func shelfItemCellDidRequestCopyPath(_ cell: ShelfItemCell) {
        guard let item = item(for: cell) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.url.path, forType: .string)
    }
}
