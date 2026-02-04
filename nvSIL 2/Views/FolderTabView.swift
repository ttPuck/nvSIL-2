import Cocoa

extension NSPasteboard.PasteboardType {
    static let folderTabID = NSPasteboard.PasteboardType("com.nvSIL.folderTabID")
}

protocol FolderTabViewDelegate: AnyObject {
    func folderTabDidClick(_ tab: FolderTabView)
    func folderTabDidDoubleClick(_ tab: FolderTabView)
    func folderTabDidRequestRename(_ tab: FolderTabView)
    func folderTabDidRequestDelete(_ tab: FolderTabView)
    func folderTab(_ tab: FolderTabView, didReceiveDroppedNoteID noteID: String)
    func folderTab(_ targetTab: FolderTabView, didReceiveReorderFromFolderID sourceFolderID: String)
}

class FolderTabView: NSView {
    weak var delegate: FolderTabViewDelegate?

    var folder: Folder? {
        didSet { updateDisplay() }
    }

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var isCompact: Bool = false {
        didSet { updateDisplay() }
    }

    var isAllTab: Bool = false {
        didSet { updateDisplay() }
    }

    private var isDragHighlighted: Bool = false {
        didSet { updateAppearance() }
    }

    private var isDragging: Bool = false
    private var dragStartPoint: NSPoint = .zero

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let hasChildrenIndicator: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: 9)
        field.textColor = .secondaryLabelColor
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private var labelWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6

        // Register as drop target for notes and tab reordering
        registerForDraggedTypes([.noteID, .folderTabID])

        addSubview(label)
        addSubview(hasChildrenIndicator)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: hasChildrenIndicator.leadingAnchor, constant: -4),

            hasChildrenIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hasChildrenIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()

        // Add tracking area for hover effect
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    private func updateDisplay() {
        if isAllTab {
            label.stringValue = "All"
            hasChildrenIndicator.stringValue = ""
            toolTip = "Show all notes in current folder"
        } else if let folder = folder {
            if isCompact {
                label.stringValue = "..."
                toolTip = folder.name
            } else {
                label.stringValue = folder.name
                toolTip = folder.hasSubfolders ? "\(folder.name) (has subfolders)" : folder.name
            }
            hasChildrenIndicator.stringValue = folder.hasSubfolders ? ">" : ""
        } else {
            label.stringValue = ""
            hasChildrenIndicator.stringValue = ""
            toolTip = nil
        }

        invalidateIntrinsicContentSize()
    }

    private func updateAppearance() {
        if isDragHighlighted {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            label.textColor = .white
            hasChildrenIndicator.textColor = .white.withAlphaComponent(0.8)
        } else if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 0
            label.textColor = .white
            hasChildrenIndicator.textColor = .white.withAlphaComponent(0.8)
        } else {
            layer?.backgroundColor = NSColor(calibratedWhite: 0.88, alpha: 1.0).cgColor
            layer?.borderWidth = 0
            label.textColor = .labelColor
            hasChildrenIndicator.textColor = .secondaryLabelColor
        }
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        let indicatorSize = hasChildrenIndicator.intrinsicContentSize
        let indicatorWidth = hasChildrenIndicator.stringValue.isEmpty ? 0 : indicatorSize.width + 4
        let width = 20 + labelSize.width + indicatorWidth + 8

        // Minimum width for "All" or compact tabs
        let minWidth: CGFloat = isAllTab ? 40 : (isCompact ? 32 : 50)
        let maxWidth: CGFloat = 150

        return NSSize(width: min(max(width, minWidth), maxWidth), height: 24)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
        isDragging = false

        if event.clickCount == 2 {
            delegate?.folderTabDidDoubleClick(self)
        } else {
            delegate?.folderTabDidClick(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Don't allow dragging the "All" tab
        guard !isAllTab, let folder = folder else { return }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let distance = hypot(currentPoint.x - dragStartPoint.x, currentPoint.y - dragStartPoint.y)

        // Start drag if moved more than 5 pixels
        if distance > 5 && !isDragging {
            isDragging = true

            let item = NSDraggingItem(pasteboardWriter: NSString(string: folder.id.uuidString))

            // Set up pasteboard
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(folder.id.uuidString, forType: .folderTabID)

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

            // Create drag image from tab
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            layer?.render(in: NSGraphicsContext.current!.cgContext)
            image.unlockFocus()

            draggingItem.setDraggingFrame(bounds, contents: image)

            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1.0).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        updateAppearance()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !isAllTab else { return }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Rename", action: #selector(requestRename), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(requestDelete), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func requestRename() {
        delegate?.folderTabDidRequestRename(self)
    }

    @objc private func requestDelete() {
        delegate?.folderTabDidRequestDelete(self)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard

        // Handle tab reordering (accept on any folder tab, not "All")
        if !isAllTab && folder != nil {
            if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.folderTabID.rawValue]) {
                // Don't highlight if dragging onto self
                if let draggedID = pasteboard.string(forType: .folderTabID),
                   let selfID = folder?.id.uuidString,
                   draggedID != selfID {
                    isDragHighlighted = true
                    return .move
                }
            }

            // Handle note drops
            if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.noteID.rawValue]) {
                isDragHighlighted = true
                return .move
            }
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isAllTab, folder != nil else {
            return []
        }

        let pasteboard = sender.draggingPasteboard

        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.folderTabID.rawValue]) {
            if let draggedID = pasteboard.string(forType: .folderTabID),
               let selfID = folder?.id.uuidString,
               draggedID != selfID {
                return .move
            }
        }

        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.noteID.rawValue]) {
            return .move
        }
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return !isAllTab && folder != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false

        guard !isAllTab, folder != nil else {
            return false
        }

        let pasteboard = sender.draggingPasteboard

        // Handle tab reordering
        if let sourceFolderID = pasteboard.string(forType: .folderTabID) {
            // Don't reorder if dropping onto self
            if sourceFolderID != folder?.id.uuidString {
                delegate?.folderTab(self, didReceiveReorderFromFolderID: sourceFolderID)
                return true
            }
        }

        // Handle note drops
        if let noteIDString = pasteboard.string(forType: .noteID) {
            delegate?.folderTab(self, didReceiveDroppedNoteID: noteIDString)
            return true
        }

        return false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
    }
}

// MARK: - NSDraggingSource

extension FolderTabView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
    }
}
