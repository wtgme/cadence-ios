import Foundation

/// Counting async semaphore — async-await-compatible analogue of `kotlinx.coroutines.sync.Semaphore`.
/// Used by `AudioBufferManager` to cap concurrent music generations to MAX_CONCURRENT_GENERATIONS,
/// matching the Android implementation.
actor GenerationSemaphore {
    private let limit: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if inUse < limit {
            inUse += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
        // inUse was bumped by release() when we were woken — no need to bump here.
    }

    func release() {
        if !waiters.isEmpty {
            let w = waiters.removeFirst()
            w.resume()
            // inUse stays — the slot is just transferred to the resumed waiter.
        } else {
            inUse -= 1
        }
    }
}
