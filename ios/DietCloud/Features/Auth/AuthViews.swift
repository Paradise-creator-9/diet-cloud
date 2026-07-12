import SwiftUI

struct AuthRootView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView("正在确认登录状态…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                AuthEmailView(viewModel: viewModel)
            case .awaitingOTP:
                AuthOTPView(viewModel: viewModel)
            case .signedIn(let user):
                SignedInPlaceholderView(user: user, viewModel: viewModel)
            }
        }
        .animation(.default, value: viewModel.phase)
    }
}

struct AuthEmailView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("膳食志")
                        .font(.largeTitle.bold())
                    Text("登录后查看你的饮食、照片和营养分析")
                        .foregroundStyle(.secondary)
                }

                Section("邮箱登录") {
                    TextField("name@example.com", text: $viewModel.emailInput)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await viewModel.sendOTP() }
                    } label: {
                        if viewModel.isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("发送登录邮件")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.isBusy || viewModel.emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let status = viewModel.statusMessage {
                    Section {
                        Text(status)
                            .font(.footnote)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section("说明") {
                    Text("主路径：打开邮件中的登录链接（Magic Link）回到本 App。请先在 Supabase Dashboard 的 Redirect URLs 中添加 dietcloud://auth-callback。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("登录")
        }
    }
}

struct AuthOTPView: View {
    @Bindable var viewModel: AuthViewModel
    private var email: String {
        if case .awaitingOTP(let value) = viewModel.phase { return value }
        return ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("登录邮件已发送至")
                    Text(email)
                        .foregroundStyle(.secondary)
                    Text("请打开邮箱中的登录链接。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("备用：验证码") {
                    Text("如果邮件中包含验证码，也可以在下方输入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("验证码（可选）", text: $viewModel.otpInput)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await viewModel.verifyOTP() }
                    } label: {
                        if viewModel.isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("用验证码登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.isBusy || viewModel.otpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let status = viewModel.statusMessage {
                    Section {
                        Text(status)
                            .font(.footnote)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button("返回修改邮箱") {
                        viewModel.backToEmailEntry()
                    }
                    Button("重新发送邮件") {
                        Task { await viewModel.sendOTP() }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .navigationTitle("完成登录")
        }
    }
}

struct SignedInPlaceholderView: View {
    let user: AuthUser
    @Bindable var viewModel: AuthViewModel
    let diaryDateKey: String

    init(user: AuthUser, viewModel: AuthViewModel, diaryDateKey: String = DiaryCalendar().dateKey()) {
        self.user = user
        self.viewModel = viewModel
        self.diaryDateKey = diaryDateKey
    }

    var body: some View {
        NavigationStack {
            List {
                Section("已登录") {
                    LabeledContent("账号", value: user.redactedEmail)
                    LabeledContent("用户 ID", value: String(user.id.prefix(8)) + "…")
                    LabeledContent("今日 dateKey", value: diaryDateKey)
                }

                Section("阶段 1") {
                    Text("Authentication 已就绪。饮食、HealthKit、AI 将在后续阶段实现。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await viewModel.signOut() }
                    } label: {
                        if viewModel.isBusy {
                            ProgressView()
                        } else {
                            Text("退出登录")
                        }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .navigationTitle("膳食志")
        }
    }
}
