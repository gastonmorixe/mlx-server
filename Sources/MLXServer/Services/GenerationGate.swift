import Foundation

/// FIFO async semaphore that serializes access to a single resource.
///
/// Used to ensure only one generation runs at a time on the model. MLX/Metal
/// command buffers are not safe under concurrent compute encoders, so requests
/// must be serialized end-to-end (prefill + decode).
public actor GenerationGate {
    private var inFlight = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func acquire() async {
        if !inFlight {
            inFlight = true
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    public func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            inFlight = false
        }
    }

    /// Run an async closure under the gate. Releases on success or throw.
    public func withLock<T: Sendable>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
}
