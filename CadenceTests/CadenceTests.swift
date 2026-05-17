import Testing
@testable import Cadence

/// Placeholder for module-level smoke tests; per-module tests live in their own files.
struct CadenceTests {
    @Test func placeholder() {
        #expect(Scene.running.displayName == "Running")
    }
}
