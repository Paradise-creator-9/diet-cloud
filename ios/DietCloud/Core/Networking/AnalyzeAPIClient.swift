import Foundation

/// Placeholder client for Phase 4 Gemini calls via Vercel.
/// Phase 0: does not perform network I/O.
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
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func analyzeMealURL() -> URL {
        provider.config.apiBaseURL.appending(path: "api/analyze-meal")
    }

    func analyzeBodyURL() -> URL {
        provider.config.apiBaseURL.appending(path: "api/analyze-body")
    }
}
