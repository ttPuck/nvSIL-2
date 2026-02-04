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
    private var dropIndicatorView: NSView?
    private var showDropIndicatorOnLeft: Bool = false

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

        // Register as drop target for notes and tab reordering
        registerForDraggedTypes([.noteID, .folderTabID])

        addSubview(label)
        addSubview(hasChildrenIndicator)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            label.trailingAnchor.constraint(lessThanOrEqualTo: hasChildrenIndicator.leadingAnchor, constant: -4),

            hasChildrenIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hasChildrenIndicator.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
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

    override func layout() {
        super.layout()
        updateTabShape()
    }

    private func updateTabShape() {
        // Create a tab shape with rounded top corners only
        let cornerRadius: CGFloat = 6
        let rect = bounds

        let path = CGMutablePath()
        // Start at bottom left
        path.move(to: CGPoint(x: 0, y: 0))
        // Line up to where the curve starts
        path.addLine(to: CGPoint(x: 0, y: rect.height - cornerRadius))
        // Top left corner curve
        path.addArc(center: CGPoint(x: cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        // Line across top
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: rect.height))
        // Top right corner curve
        path.addArc(center: CGPoint(x: rect.width - cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        // Line down to bottom right
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        // Close the path
        path.closeSubpath()

        let maskLayer = CAShapeLayer()
        maskLayer.path = path
        layer?.mask = maskLayer
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
            // Drag highlight state
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
            layer?.shadowOpacity = 0.3
            layer?.shadowRadius = 2
            layer?.shadowOffset = CGSize(width: 0, height: 1)
            layer?.shadowColor = NSColor.black.cgColor
            label.textColor = .labelColor
            hasChildrenIndicator.textColor = .secondaryLabelColor
        } else if isSelected {
            // Selected tab - looks "attached" to content below
            layer?.backgroundColor = NSColor.white.cgColor
            layer?.shadowOpacity = 0.15
            layer?.shadowRadius = 2
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            layer?.shadowColor = NSColor.black.cgColor
            label.textColor = .labelColor
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            hasChildrenIndicator.textColor = .secondaryLabelColor
        } else {
            // Unselected tab - slightly recessed appearance
            layer?.backgroundColor = NSColor(calibratedWhite: 0.92, alpha: 1.0).cgColor
            layer?.shadowOpacity = 0
            label.textColor = .secondaryLabelColor
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            hasChildrenIndicator.textColor = .tertiaryLabelColor
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

        return NSSize(width: min(max(width, minWidth), maxWidth), height: 26)
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

        // Start drag if moved more than 3 pixels (reduced for easier dragging)
        if distance > 3 && !isDragging {
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
        if !isSelected && !isDragHighlighted {
            // Subtle hover effect - slightly lighter
            layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1.0).cgColor
            layer?.shadowOpacity = 0.1
            layer?.shadowRadius = 1
            layer?.shadowOffset = CGSize(width: 0, height: 1)
            layer?.shadowColor = NSColor.black.cgColor
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

    // MARK: - Drop Indicator

    private func showDropIndicator(onLeft: Bool) {
        if dropIndicatorView == nil {
            let indicator = NSView()
            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            indicator.layer?.cornerRadius = 2
            addSubview(indicator)
            dropIndicatorView = indicator
        }

        // Larger, more visible drop indicator
        let indicatorWidth: CGFloat = 4
        let indicatorHeight: CGFloat = bounds.height + 4  // Extend beyond tab height

        if onLeft {
            dropIndicatorView?.frame = NSRect(x: -indicatorWidth / 2 - 2,
                                               y: -2,
                                               width: indicatorWidth,
                                               height: indicatorHeight)
        } else {
            dropIndicatorView?.frame = NSRect(x: bounds.width - indicatorWidth / 2 + 2,
                                               y: -2,
                                               width: indicatorWidth,
                                               height: indicatorHeight)
        }
        dropIndicatorView?.isHidden = false
    }

    private func hideDropIndicator() {
        dropIndicatorView?.isHidden = true
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
                    // Highlight the tab and show drop indicator
                    isDragHighlighted = true
                    let location = convert(sender.draggingLocation, from: nil)
                    showDropIndicatorOnLeft = location.x < bounds.width / 2
                    showDropIndicator(onLeft: showDropIndicatorOnLeft)
                    return .move
                }
            }
        }

        // Handle note drops - allow on both folder tabs AND "All" tab (to move to parent folder)
        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.noteID.rawValue]) {
            isDragHighlighted = true
            return .move
        }

        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard

        // Handle tab reordering (not on "All" tab)
        if !isAllTab && folder != nil {
            if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.folderTabID.rawValue]) {
                if let draggedID = pasteboard.string(forType: .folderTabID),
                   let selfID = folder?.id.uuidString,
                   draggedID != selfID {
                    // Keep tab highlighted and update drop indicator position
                    isDragHighlighted = true
                    let location = convert(sender.draggingLocation, from: nil)
                    let newSide = location.x < bounds.width / 2
                    if newSide != showDropIndicatorOnLeft {
                        showDropIndicatorOnLeft = newSide
                        showDropIndicator(onLeft: showDropIndicatorOnLeft)
                    }
                    return .move
                }
            }
        }

        // Handle note drops - allow on both folder tabs AND "All" tab
        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.noteID.rawValue]) {
            return .move
        }

        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
        hideDropIndicator()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Allow note drops on any tab (including "All" tab)
        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.noteID.rawValue]) {
            return true
        }

        // Tab reordering only on folder tabs (not "All")
        return !isAllTab && folder != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        hideDropIndicator()

        let pasteboard = sender.draggingPasteboard

        // Handle note drops - works on both folder tabs and "All" tab
        if let noteIDString = pasteboard.string(forType: .noteID) {
            delegate?.folderTab(self, didReceiveDroppedNoteID: noteIDString)
            return true
        }

        // Handle tab reordering (only on folder tabs, not "All")
        if !isAllTab && folder != nil {
            if let sourceFolderID = pasteboard.string(forType: .folderTabID) {
                // Don't reorder if dropping onto self
                if sourceFolderID != folder?.id.uuidString {
                    delegate?.folderTab(self, didReceiveReorderFromFolderID: sourceFolderID)
                    return true
                }
            }
        }

        return false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
        hideDropIndicator()
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
