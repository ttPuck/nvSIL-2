import Foundation

class Folder: Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    weak var parent: Folder?
    var subfolders: [Folder]
    var isExpanded: Bool

    var hasSubfolders: Bool {
        return !subfolders.isEmpty
    }

    var depth: Int {
        var count = 0
        var current = parent
        while current != nil {
            count += 1
            current = current?.parent
        }
        return count
    }

    var path: [Folder] {
        var result: [Folder] = []
        var current: Folder? = self
        while let folder = current {
            result.insert(folder, at: 0)
            current = folder.parent
        }
        return result
    }

    var isRoot: Bool {
        return parent == nil
    }

    init(name: String, url: URL, parent: Folder? = nil) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.parent = parent
        self.subfolders = []
        self.isExpanded = false
    }

    static func == (lhs: Folder, rhs: Folder) -> Bool {
        return lhs.url == rhs.url
    }

    func subfolder(named name: String) -> Folder? {
        return subfolders.first { $0.name.lowercased() == name.lowercased() }
    }

    func findFolder(byURL url: URL) -> Folder? {
        if self.url == url { return self }
        for subfolder in subfolders {
            if let found = subfolder.findFolder(byURL: url) {
                return found
            }
        }
        return nil
    }

    func sortSubfolders() {
        subfolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
