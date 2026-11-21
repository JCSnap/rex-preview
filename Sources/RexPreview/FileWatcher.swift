import Foundation

/// Watches a local file for modifications (including atomic rename-over-file saves)
/// and invokes `onChange` on the main queue, debounced.
@MainActor
final class FileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceTask: Task<Void, Never>?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        stop()
        let path = url.path
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // Atomic editor save replaced the inode; re-arm watcher shortly.
                self.scheduleReload(rearm: true)
            } else {
                self.scheduleReload(rearm: false)
            }
        }
        let capturedFD = fd
        src.setCancelHandler {
            close(capturedFD)
        }
        source = src
        src.resume()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        fd = -1
    }

    private func scheduleReload(rearm: Bool) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            if rearm {
                self.start()
            }
            self.onChange()
        }
    }
}
