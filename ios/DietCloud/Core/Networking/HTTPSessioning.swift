import Foundation

/// Thin URLSession abstraction for unit tests (no real network in tests).
protocol HTTPSessioning: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSessioning {}
