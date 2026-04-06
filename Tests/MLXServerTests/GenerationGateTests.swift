import Foundation
import Testing

@testable import MLXServer

@Test func gate_acquireRelease_singleAccess() async {
    let gate = GenerationGate()
    await gate.acquire()
    // Holding the gate; no other waiters
    await gate.release()
    // Should be reusable
    await gate.acquire()
    await gate.release()
}

@Test func gate_serializesConcurrentAcquires() async {
    let gate = GenerationGate()
    let recorder = OrderRecorder()

    // Task A grabs the gate, holds for a moment, then releases
    let taskA = Task {
        await gate.acquire()
        await recorder.append("A-acquired")
        try? await Task.sleep(for: .milliseconds(50))
        await recorder.append("A-releasing")
        await gate.release()
    }

    // Give A a head start so it definitely acquires first
    try? await Task.sleep(for: .milliseconds(10))

    // Task B should block until A releases
    let taskB = Task {
        await gate.acquire()
        await recorder.append("B-acquired")
        await gate.release()
    }

    await taskA.value
    await taskB.value

    let order = await recorder.events
    #expect(order == ["A-acquired", "A-releasing", "B-acquired"])
}

@Test func gate_fifoOrderingForMultipleWaiters() async {
    let gate = GenerationGate()
    let recorder = OrderRecorder()

    // Hold the gate
    await gate.acquire()

    // Queue up three waiters in order
    let task1 = Task {
        await gate.acquire()
        await recorder.append("1")
        await gate.release()
    }
    try? await Task.sleep(for: .milliseconds(10))
    let task2 = Task {
        await gate.acquire()
        await recorder.append("2")
        await gate.release()
    }
    try? await Task.sleep(for: .milliseconds(10))
    let task3 = Task {
        await gate.acquire()
        await recorder.append("3")
        await gate.release()
    }
    try? await Task.sleep(for: .milliseconds(10))

    // Release the original holder; waiters drain in FIFO order
    await gate.release()

    await task1.value
    await task2.value
    await task3.value

    let order = await recorder.events
    #expect(order == ["1", "2", "3"])
}

@Test func gate_withLockReleasesOnError() async {
    let gate = GenerationGate()

    struct TestError: Error {}

    do {
        try await gate.withLock {
            throw TestError()
        }
        Issue.record("Expected throw")
    } catch is TestError {
        // expected
    } catch {
        Issue.record("Wrong error: \(error)")
    }

    // Gate should be released; this acquire must succeed promptly
    let task = Task {
        await gate.acquire()
        await gate.release()
    }
    await task.value
}

@Test func gate_withLockReleasesOnSuccess() async throws {
    let gate = GenerationGate()
    let result = try await gate.withLock { () -> Int in
        return 42
    }
    #expect(result == 42)

    // Re-acquire after success
    await gate.acquire()
    await gate.release()
}

actor OrderRecorder {
    var events: [String] = []
    func append(_ s: String) { events.append(s) }
}
