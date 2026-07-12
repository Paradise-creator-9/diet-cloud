import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    LabeledContent("账号", value: viewModel.user.redactedEmail)
                    Text("用户标识不会完整显示；登录状态保存在本机钥匙串。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("每日目标") {
                    TextField("目标热量 kcal", text: $viewModel.draftCalories)
                        .keyboardType(.decimalPad)
                    TextField("目标体重 kg", text: $viewModel.draftWeight)
                        .keyboardType(.decimalPad)
                    TextField("蛋白质 g", text: $viewModel.draftProtein)
                        .keyboardType(.decimalPad)
                    TextField("碳水 g", text: $viewModel.draftCarbs)
                        .keyboardType(.decimalPad)
                    TextField("膳食纤维 g", text: $viewModel.draftFiber)
                        .keyboardType(.decimalPad)
                    Text("目标保存在本机，不写入云端数据库。留空表示不设置该项。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("保存目标") {
                        _ = viewModel.saveGoals()
                    }
                }

                Section("提醒") {
                    LabeledContent("通知权限", value: viewModel.notificationAuthStatus.displayTitle)

                    if viewModel.notificationAuthStatus == .denied {
                        Button("前往系统设置") {
                            openSystemSettings()
                        }
                        .accessibilityLabel("前往系统设置开启通知")
                    }

                    if viewModel.notificationAuthStatus == .provisional {
                        Text("当前为临时授权，提醒可能以静默横幅形式送达。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(ReminderKind.allCases) { kind in
                        reminderRow(kind)
                    }

                    if let message = viewModel.reminderStatusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if viewModel.hasScheduleFailure {
                        Button("重试更新通知") {
                            Task { await viewModel.retrySchedule() }
                        }
                        .accessibilityLabel("重试更新本地通知调度")
                    }

                    Text("提醒仅保存在本机，不会上传云端。首次开启时会请求通知权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("数据源") {
                    Text("Apple 健康：在饮食页使用「从健康导入」只读同步所选日期的步数、活动、距离、体重与运动。不会向健康写入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("餐食照片与饮食记录：经 Supabase 账户同步；目标与提醒设置仅本地。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let status = viewModel.statusMessage {
                    Section {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        viewModel.requestSignOut()
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("退出登录？", isPresented: $viewModel.isPresentingSignOutConfirm) {
                Button("取消", role: .cancel) {
                    viewModel.cancelSignOut()
                }
                Button("退出", role: .destructive) {
                    viewModel.confirmSignOut()
                    dismiss()
                }
            } message: {
                Text("退出后需重新使用邮箱登录。本地目标与提醒设置会保留在本机。")
            }
            .onAppear {
                viewModel.loadDraftsFromStore()
                viewModel.loadReminderSettingsFromStore()
                Task { await viewModel.refreshNotificationAuthorizationAndReconcile() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await viewModel.refreshNotificationAuthorizationAndReconcile() }
                }
            }
        }
    }

    @ViewBuilder
    private func reminderRow(_ kind: ReminderKind) -> some View {
        let item = viewModel.reminderSettings[kind]
        VStack(alignment: .leading, spacing: 8) {
            Toggle(kind.title, isOn: Binding(
                get: { viewModel.reminderSettings[kind].isEnabled },
                set: { newValue in
                    Task { await viewModel.setReminderEnabled(kind, enabled: newValue) }
                }
            ))
            .accessibilityLabel(kind.title)

            if item.isEnabled {
                DatePicker(
                    "时间",
                    selection: Binding(
                        get: { viewModel.bindingDate(for: kind) },
                        set: { newDate in
                            Task { await viewModel.setReminderTime(kind, date: newDate) }
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityLabel("\(kind.title)时间")
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
