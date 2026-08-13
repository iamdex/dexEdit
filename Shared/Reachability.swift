import Foundation
import Network

/// Whether this device can reach a network at all.
///
/// Not a claim that iCloud is up, or that anything will actually arrive — only
/// that asking is worth the battery. The app puts it to two uses: it stops
/// pestering the file provider for a download that cannot possibly come, and it
/// lets a waiting note say which kind of waiting it is doing.
final class Reachability {
    private(set) var isOnline = true

    /// Called on the main queue whenever the answer changes — never for a
    /// repeat of the answer already given.
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.espertini.dexEdit.reachability")

    /// Starts optimistic. The first real answer lands within a moment of
    /// launch, and guessing "online" until then keeps a cold start from
    /// briefly announcing a problem the device may not have.
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                self.onChange?(online)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
