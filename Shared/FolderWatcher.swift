import Foundation

/// Listens to the notes folder, so a note written on another device turns up
/// while the app is sitting open.
///
/// Before this, the app only looked at the folder when it came to the front —
/// and because the look itself was an uncoordinated enumeration, even that
/// often missed a file iCloud had brought down. Nothing short of relaunching
/// showed it.
///
/// Registering as a presenter is also what earns the app the right to be told,
/// rather than to keep asking: the file provider now announces changes instead
/// of the app polling for them.
final class FolderWatcher: NSObject, NSFilePresenter {
    /// Several announcements arrive for one change — a file appearing, then
    /// changing, then its parent changing. Re-reading the folder once for each
    /// would be silly, so they are collected and answered once.
    private static let settleDelay: TimeInterval = 0.4

    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .main

    private let onChange: () -> Void
    private var pending: DispatchWorkItem?

    init(folder: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = folder
        self.onChange = onChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    /// Must be called before dropping the watcher. A presenter that is never
    /// removed keeps being sent messages, and keeps the folder claimed.
    func stop() {
        pending?.cancel()
        pending = nil
        NSFileCoordinator.removeFilePresenter(self)
    }

    // MARK: - NSFilePresenter

    func presentedItemDidChange() { scheduleRefresh() }
    func presentedSubitemDidChange(at url: URL) { scheduleRefresh() }
    func presentedSubitemDidAppear(at url: URL) { scheduleRefresh() }

    func accommodatePresentedSubitemDeletion(
        at url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        scheduleRefresh()
        completionHandler(nil)
    }

    private func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }
}
