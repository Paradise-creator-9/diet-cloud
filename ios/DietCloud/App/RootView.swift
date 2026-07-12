import SwiftUI

/// Phase 0 placeholder shell — not a formal login or diary UI.
struct RootView: View {
    let container: AppDependencyContainer

    var body: some View {
        NavigationStack {
            List {
                Section("膳食志 · 阶段 0") {
                    LabeledContent("工程状态", value: "骨架已就绪")
                    LabeledContent("今日 dateKey", value: container.diaryCalendar.dateKey())
                }

                Section("客户端配置（公开）") {
                    LabeledContent("Supabase host", value: container.config.supabaseURL.host ?? "—")
                    LabeledContent("API base host", value: container.config.apiBaseURL.host ?? "—")
                    LabeledContent("Storage bucket", value: container.config.storageBucket)
                    LabeledContent(
                        "配置状态",
                        value: container.config.isReadyForNetwork ? "可联网（非占位）" : "占位 / 未就绪"
                    )
                }

                Section("后续阶段（未实现）") {
                    Text(AppError.notImplemented("Email OTP 登录").userMessage)
                    Text(AppError.notImplemented("饮食 CRUD").userMessage)
                    Text(AppError.notImplemented("HealthKit / AI").userMessage)
                }

                Section("安全边界") {
                    Text("App 仅使用 Supabase URL + anon key + 用户 Session。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("禁止：SERVICE_ROLE、GEMINI_API_KEY、DIARY_INGEST_TOKEN。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Shortcuts / activity-ingest 不属于 App 数据层。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("膳食志")
        }
    }
}

#Preview {
    RootView(
        container: AppDependencyContainer(
            config: AppConfig(
                supabaseURL: URL(string: "https://YOUR_PROJECT.supabase.co")!,
                supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
                apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
                storageBucket: "meal-photos"
            )
        )
    )
}
