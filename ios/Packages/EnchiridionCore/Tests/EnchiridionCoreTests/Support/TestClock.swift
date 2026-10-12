import Foundation
import Synchronization
import Testing

/// A manual clock: time moves only when a test calls `advance(by:)`. Sleepers whose deadline has passed resume, in
/// deadline order; a cancelled sleeper throws `CancellationError`.
final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        var id: Int
        var deadline: Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
        var nextID = 0
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// Sleepers waiting right now.
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resume: Result<Void, any Error>? = state.withLock { state in
                    if state.cancelled.remove(id) != nil { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(()) }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let resume { continuation.resume(with: resume) }
            }
        } onCancel: {
            let sleeper: Sleeper? = state.withLock { state in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    state.cancelled.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and resumes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        let due: [Sleeper] = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Waits (in real time, up to 5 s) until exactly `count` sleepers are waiting.
    func waitForSleepers(_ count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while sleeperCount != count {
            if ContinuousClock.now > deadline {
                Issue.record("Timed out waiting for \(count) sleepers (have \(sleeperCount))",
                             sourceLocation: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
