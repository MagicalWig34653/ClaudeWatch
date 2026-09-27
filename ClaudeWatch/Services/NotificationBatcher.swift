import Foundation

/// Collects notifications for a fixed window and hands them over as one group.
///
/// The window starts with the first item and does not slide, so no notification is
/// delayed by more than the window. A window of 0 delivers every item immediately.
@MainActor
final class NotificationBatcher<Item> {
    private let window: () -> TimeInterval
    private let deliver: ([Item]) async -> Void
    private var pending: [Item] = []
    private var timer: Task<Void, Never>?

    init(window: @escaping () -> TimeInterval, deliver: @escaping ([Item]) async -> Void) {
        self.window = window
        self.deliver = deliver
    }

    var pendingCount: Int { pending.count }

    func add(_ item: Item) async {
        let window = window()
        guard window > 0 else {
            await deliver([item])
            return
        }
        pending.append(item)
        guard timer == nil else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush(cancellingTimer: false)
        }
    }

    /// Delivers everything collected so far right away.
    func flush() async {
        await flush(cancellingTimer: true)
    }

    private func flush(cancellingTimer: Bool) async {
        // Only cancel a sleeping timer; cancelling the running timer task would also
        // cancel the network requests made while delivering.
        if cancellingTimer { timer?.cancel() }
        timer = nil
        let items = pending
        pending = []
        guard !items.isEmpty else { return }
        await deliver(items)
    }
}
