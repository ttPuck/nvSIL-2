import Cocoa

protocol TabContainerViewDelegate: AnyObject {
    func tabContainer(_ container: TabContainerView, didSelectFolder folder: Folder?)
    func tabContainer(_ container: TabContainerView, didNavigateIntoFolder folder: Folder)
    func tabContainer(_ container: TabContainerView, didRequestNewSubfolderIn parent: Folder?)
    func tabContainer(_ container: TabContainerView, didRequestRenameFolder folder: Folder)
    func tabContainer(_ container: TabContainerView, didRequestDeleteFolder folder: Folder)
    func tabContainerDidSelectTodoTab(_ container: TabContainerView)
    func tabContainer(_ container: TabContainerView, didReceiveDroppedNoteID noteID: String, onFolder folder: Folder)
    func tabContainer(_ container: TabContainerView, didReorderFolder folder: Folder, toIndex index: Int)
}

class TabContainerView: NSView, FolderTabViewDelegate {
    weak var delegate: TabContainerViewDelegate?

    private var scrollView: NSScrollView!
    private var tabStackView: NSStackView!
    private var allTab: FolderTabView!
    private var addButton: NSButton!
    private var todoButton: NSButton!
    private var backButton: NSButton!

    private var folderTabs: [FolderTabView] = []
    private(set) var currentFolder: Folder?
    private var selectedFolder: Folder?
    private var isTodoSelected: Bool = false

    var displayedSubfolders: [Folder] = [] {
        didSet { rebuildTabs() }
    }

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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor

        // Create back button
        backButton = NSButton()
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.bezelStyle = .inline
        backButton.title = "<"
        backButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        backButton.target = self
        backButton.action = #selector(backButtonClicked)
        backButton.toolTip = "Go to parent folder"
        backButton.isHidden = true

        // Create "All" tab
        allTab = FolderTabView()
        allTab.translatesAutoresizingMaskIntoConstraints = false
        allTab.isAllTab = true
        allTab.delegate = self

        // Create scroll view for tabs
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Create stack view for folder tabs
        tabStackView = NSStackView()
        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabStackView.orientation = .horizontal
        tabStackView.spacing = 4
        tabStackView.alignment = .centerY
        tabStackView.distribution = .fill

        scrollView.documentView = tabStackView

        // Create "+" button
        addButton = NSButton()
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .inline
        addButton.title = "+"
        addButton.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        addButton.target = self
        addButton.action = #selector(addButtonClicked)
        addButton.toolTip = "Create new subfolder"

        // Create "TODO" button
        todoButton = NSButton()
        todoButton.translatesAutoresizingMaskIntoConstraints = false
        todoButton.bezelStyle = .inline
        todoButton.title = "TODO"
        todoButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        todoButton.target = self
        todoButton.action = #selector(todoButtonClicked)
        todoButton.toolTip = "Show TODO items"

        addSubview(backButton)
        addSubview(allTab)
        addSubview(scrollView)
        addSubview(addButton)
        addSubview(todoButton)

        NSLayoutConstraint.activate([
            // Back button
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24),
            backButton.heightAnchor.constraint(equalToConstant: 24),

            // All tab
            allTab.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            allTab.centerYAnchor.constraint(equalTo: centerYAnchor),
            allTab.heightAnchor.constraint(equalToConstant: 24),

            // Scroll view for folder tabs
            scrollView.leadingAnchor.constraint(equalTo: allTab.trailingAnchor, constant: 4),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            scrollView.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),

            // Stack view inside scroll view
            tabStackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            tabStackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),

            // Add button
            addButton.trailingAnchor.constraint(equalTo: todoButton.leadingAnchor, constant: -8),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 24),

            // TODO button on the right
            todoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            todoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            todoButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        updateAllTabSelection()
    }

    private func updateAllTabSelection() {
        allTab.isSelected = (selectedFolder == nil && !isTodoSelected)
    }

    private func rebuildTabs() {
        // Remove existing folder tabs
        for tab in folderTabs {
            tab.removeFromSuperview()
        }
        folderTabs.removeAll()

        // Calculate available width for tabs
        let availableWidth = scrollView.bounds.width
        var usedWidth: CGFloat = 0
        let maxTabWidth: CGFloat = 120

        for (index, folder) in displayedSubfolders.enumerated() {
            let tab = FolderTabView()
            tab.translatesAutoresizingMaskIntoConstraints = false
            tab.folder = folder
            tab.delegate = self

            // Determine if tab should be compact (for overflow)
            let estimatedWidth = min(tab.intrinsicContentSize.width, maxTabWidth)
            let remainingFolders = displayedSubfolders.count - index - 1
            let spaceNeeded = estimatedWidth + (CGFloat(remainingFolders) * 36) // 36 = compact width estimate

            if usedWidth + spaceNeeded > availableWidth - 10 && !folderTabs.isEmpty && remainingFolders > 0 {
                tab.isCompact = true
            }

            tab.isSelected = (folder === selectedFolder)

            tabStackView.addArrangedSubview(tab)
            folderTabs.append(tab)

            NSLayoutConstraint.activate([
                tab.heightAnchor.constraint(equalToConstant: 24),
                tab.widthAnchor.constraint(lessThanOrEqualToConstant: maxTabWidth)
            ])

            usedWidth += tab.intrinsicContentSize.width + 4
        }
    }

    func setCurrentFolder(_ folder: Folder?) {
        currentFolder = folder
        displayedSubfolders = folder?.subfolders ?? []

        // Update back button visibility
        backButton.isHidden = (folder?.parent == nil)

        // Reset selection to "All" tab
        selectedFolder = nil
        isTodoSelected = false
        updateTabSelections()
    }

    func selectFolder(_ folder: Folder?) {
        selectedFolder = folder
        isTodoSelected = false
        updateTabSelections()
    }

    private func updateTabSelections() {
        updateAllTabSelection()

        for tab in folderTabs {
            tab.isSelected = (tab.folder === selectedFolder)
        }

        // Update TODO button appearance
        if isTodoSelected {
            todoButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            todoButton.layer?.backgroundColor = nil
        }
    }

    // MARK: - FolderTabViewDelegate

    func folderTabDidClick(_ tab: FolderTabView) {
        isTodoSelected = false

        if tab.isAllTab {
            selectedFolder = nil
            updateTabSelections()
            delegate?.tabContainer(self, didSelectFolder: nil)
        } else if let folder = tab.folder {
            selectedFolder = folder
            updateTabSelections()
            delegate?.tabContainer(self, didSelectFolder: folder)
        }
    }

    func folderTabDidDoubleClick(_ tab: FolderTabView) {
        guard !tab.isAllTab, let folder = tab.folder, folder.hasSubfolders else { return }

        // Navigate into this folder
        delegate?.tabContainer(self, didNavigateIntoFolder: folder)
    }

    func folderTabDidRequestRename(_ tab: FolderTabView) {
        guard let folder = tab.folder else { return }
        delegate?.tabContainer(self, didRequestRenameFolder: folder)
    }

    func folderTabDidRequestDelete(_ tab: FolderTabView) {
        guard let folder = tab.folder else { return }
        delegate?.tabContainer(self, didRequestDeleteFolder: folder)
    }

    func folderTab(_ tab: FolderTabView, didReceiveDroppedNoteID noteID: String) {
        guard let folder = tab.folder else { return }
        delegate?.tabContainer(self, didReceiveDroppedNoteID: noteID, onFolder: folder)
    }

    func folderTab(_ targetTab: FolderTabView, didReceiveReorderFromFolderID sourceFolderID: String) {
        guard let targetFolder = targetTab.folder,
              let sourceUUID = UUID(uuidString: sourceFolderID),
              let sourceIndex = displayedSubfolders.firstIndex(where: { $0.id == sourceUUID }),
              let targetIndex = displayedSubfolders.firstIndex(where: { $0 === targetFolder }) else {
            return
        }

        // Move the folder in the array
        let sourceFolder = displayedSubfolders[sourceIndex]

        // Calculate the new index accounting for removal
        var newIndex = targetIndex
        if sourceIndex < targetIndex {
            newIndex -= 1
        }

        displayedSubfolders.remove(at: sourceIndex)
        displayedSubfolders.insert(sourceFolder, at: newIndex)

        // Rebuild tabs to reflect new order
        rebuildTabs()

        // Notify delegate
        delegate?.tabContainer(self, didReorderFolder: sourceFolder, toIndex: newIndex)
    }

    // MARK: - Actions

    @objc private func backButtonClicked() {
        guard let parent = currentFolder?.parent else { return }
        delegate?.tabContainer(self, didNavigateIntoFolder: parent)
    }

    @objc private func addButtonClicked() {
        delegate?.tabContainer(self, didRequestNewSubfolderIn: currentFolder)
    }

    @objc private func todoButtonClicked() {
        isTodoSelected = !isTodoSelected
        if isTodoSelected {
            selectedFolder = nil
        }
        updateTabSelections()
        delegate?.tabContainerDidSelectTodoTab(self)
    }

    func deselectTodo() {
        isTodoSelected = false
        updateTabSelections()
    }
}
