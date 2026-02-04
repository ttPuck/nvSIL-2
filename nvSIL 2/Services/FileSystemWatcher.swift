import Foundation

class FileSystemWatcher {
    private var dispatchSources: [Int32: DispatchSourceFileSystemObject] = [:]
    private let monitoredDirectory: URL
    private var watchedDescriptors: [Int32] = []
    private let fileManager = FileManager.default

    var onDirectoryChange: (() -> Void)?
    var onSubdirectoryAdded: ((URL) -> Void)?
    var onSubdirectoryRemoved: ((URL) -> Void)?

    init(monitoredDirectory: URL) {
        self.monitoredDirectory = monitoredDirectory
    }

    func startWatching() {
        stopWatching()
        watchDirectory(monitoredDirectory)
        watchSubdirectoriesRecursively(in: monitoredDirectory)
    }

    private func watchDirectory(_ directory: URL) {
        let path = directory.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        watchedDescriptors.append(fd)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.global(qos: .background)
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.onDirectoryChange?()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        dispatchSources[fd] = source
    }

    private func watchSubdirectoriesRecursively(in directory: URL) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                watchDirectory(url)
            }
        }
    }

    func stopWatching() {
        for (_, source) in dispatchSources {
            source.cancel()
        }
        dispatchSources.removeAll()
        watchedDescriptors.removeAll()
    }

    func refreshWatchers() {
        stopWatching()
        startWatching()
    }

    deinit {
        stopWatching()
    }
}
