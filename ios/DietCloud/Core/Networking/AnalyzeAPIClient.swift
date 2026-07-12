import Foundation

/// Placeholder client for Phase 4 Gemini calls via Vercel.
/// Phase 0/1: does not perform network I/O.
///
/// Contract (for later):
/// - POST `{API_BASE}/api/analyze-meal` or `/api/analyze-body`
/// - Header: `Authorization: Bearer <supabase_access_token>`
/// - Never embed `GEMINI_API_KEY` in the app
protocol AnalyzeAPIClienting: Sendable {
    func analyzeMealURL() -> URL
    func analyzeBodyURL() -> URL
}

struct AnalyzeAPIClient: AnalyzeAPIClienting {
    private let apiBaseURL: URL

    init(provider: SupabaseClientProviding) {
        self.apiBaseURL = provider.config.apiBaseURL
    }

    init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    func analyzeMealURL() -> URL {
        apiBaseURL.appending(path: "api/analyze-meal")
    }

    func analyzeBodyURL() -> URL {
        apiBaseURL.appending(path: "api/analyze-body")
    }
}
