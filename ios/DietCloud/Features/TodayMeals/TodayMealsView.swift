import PhotosUI
import SwiftUI

struct TodayMealsView: View {
    @Bindable var viewModel: TodayMealsViewModel
    let onSignOut: () -> Void
    @State private var isPresentingSettings = false
    @State private var isPresentingSignOutConfirm = false
    @State private var isShowingTrends = false
    @State private var isShowingPhotoLibrary = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Text(viewModel.user.redactedEmail)
                            Button("设置") {
                                isPresentingSettings = true
                            }
                            Button("退出登录", role: .destructive) {
                                isPresentingSignOutConfirm = true
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 14) {
                            Button {
                                isShowingPhotoLibrary = true
                            } label: {
                                Image(systemName: "photo.on.rectangle")
                            }
                            .accessibilityLabel("照片库")

                            Button {
                                isShowingTrends = true
                            } label: {
                                Image(systemName: "chart.xyaxis.line")
                            }
                            .accessibilityLabel("趋势与统计")

                            Button {
                                isPresentingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("设置")

                            Button {
                                viewModel.openAddSheet()
                            } label: {
                                Label("添加", systemImage: "plus.circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.body.weight(.semibold))
                            }
                            .accessibilityLabel("新增食物")
                            .disabled(viewModel.isPresentingAddSheet)
                        }
                    }
                }
                .navigationDestination(isPresented: $isShowingTrends) {
                    TrendsView(viewModel: viewModel.makeTrendsViewModel())
                }
                .navigationDestination(isPresented: $isShowingPhotoLibrary) {
                    PhotoLibraryView(viewModel: viewModel.makePhotoLibraryViewModel())
                }
                .sheet(isPresented: $viewModel.isPresentingAddSheet, onDismiss: {
                    viewModel.handleFoodFormDismissed()
                }) {
                    AddFoodItemView(viewModel: viewModel)
                        .interactiveDismissDisabled(viewModel.isAnalyzing || viewModel.isMutating)
                }
                .sheet(isPresented: $viewModel.isPresentingBodySheet, onDismiss: {
                    // Swipe-dismiss: drop screenshot memory; keep no lingering AI session.
                    if !viewModel.isPresentingBodySheet {
                        viewModel.clearBodySessionAfterDismiss()
                    }
                }) {
                    BodyMetricEditView(viewModel: viewModel)
                        .interactiveDismissDisabled(viewModel.isAnalyzingBody || viewModel.isMutating)
                }
                .sheet(isPresented: $viewModel.isPresentingActivitySheet) {
                    DailyActivityEditView(viewModel: viewModel)
                }
                .sheet(isPresented: $viewModel.isPresentingExerciseSheet) {
                    ExerciseEditView(viewModel: viewModel)
                }
                .sheet(isPresented: $isPresentingSettings, onDismiss: {
                    viewModel.reloadGoals()
                }) {
                    SettingsView(
                        viewModel: viewModel.makeSettingsViewModel(onSignOut: {
                            isPresentingSettings = false
                            onSignOut()
                        })
                    )
                }
                .sheet(isPresented: $viewModel.isPresentingFavoritesManageSheet, onDismiss: {
                    viewModel.closeFavoritesManageSheet()
                }) {
                    FavoriteFoodsManageView(viewModel: viewModel)
                }
                .alert("退出登录？", isPresented: $isPresentingSignOutConfirm) {
                    Button("取消", role: .cancel) {}
                    Button("退出", role: .destructive, action: onSignOut)
                } message: {
                    Text("退出后需重新使用邮箱登录。本地目标设置会保留在本机。")
                }
                .task {
                    viewModel.reloadGoals()
                    viewModel.reloadFavoriteFoods()
                    await viewModel.load()
                }
                .refreshable {
                    viewModel.reloadGoals()
                    viewModel.reloadFavoriteFoods()
                    await viewModel.load()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            DiaryDateBar(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))

            Group {
                switch viewModel.loadState {
                case .loading:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("正在加载 \(viewModel.displayTitle)…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("饮食、身体与活动数据")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                case .error(let message):
                    ContentUnavailableView {
                        Label("无法加载", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await viewModel.load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .background(Color(.systemGroupedBackground))
                case .empty, .loaded:
                    List {
                        // Compact overview scrolls with the list (not pinned / sticky).
                        Section {
                            DayEnergySummaryCard(
                                energy: viewModel.dayEnergySummary,
                                progress: viewModel.goalsProgress
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                            HealthKitImportBar(viewModel: viewModel)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        Section {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.displayTitle)
                                        .font(.title3.weight(.semibold))
                                    Text(viewModel.selectedDateKey)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                                Spacer()
                                if !viewModel.isToday {
                                    Text("补记")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                        }

                        BodyMetricSection(viewModel: viewModel)
                        DailyActivitySection(viewModel: viewModel)
                        ExerciseSection(viewModel: viewModel)

                        FavoriteFoodsSection(viewModel: viewModel)

                        Section {
                            if case .empty = viewModel.loadState {
                                ContentUnavailableView(
                                    "还没有饮食记录",
                                    systemImage: "fork.knife",
                                    description: Text(
                                        viewModel.isToday
                                            ? "点右上角「添加」记录餐食，可附照片与 AI 分析。"
                                            : "点右上角「添加」为 \(viewModel.displayTitle) 补记。"
                                    )
                                )
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text("饮食记录")
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                                .foregroundStyle(.primary)
                        }

                        ForEach(viewModel.mealSections, id: \.meal) { section in
                            MealSectionView(
                                group: section,
                                isMutating: viewModel.isMutating,
                                onAdd: { viewModel.openAddSheet(defaultMeal: section.meal) },
                                onEdit: { item in
                                    viewModel.openEdit(item)
                                },
                                onAddToFavorites: { item in
                                    viewModel.addFoodItemToFavorites(item)
                                },
                                onDelete: { item in
                                    Task { await viewModel.deleteItem(item) }
                                }
                            )
                        }

                        if let favoriteStatus = viewModel.favoriteStatusMessage {
                            Section {
                                Text(favoriteStatus)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let status = viewModel.statusMessage {
                            Section {
                                Text(status)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let error = viewModel.errorMessage, viewModel.loadState != .error(error) {
                            Section {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                    .alert("用健康数据更新？", isPresented: $viewModel.isPresentingHealthKitOverwriteConfirm) {
                        Button("取消", role: .cancel) {
                            viewModel.cancelHealthKitOverwriteImport()
                        }
                        Button("用健康数据更新", role: .destructive) {
                            Task { await viewModel.confirmHealthKitOverwriteImport() }
                        }
                    } message: {
                        Text("今天（所选日期）已有手动身体或每日活动记录。确认后将用 Apple 健康数据更新这些项；运动记录会去重后追加。不会向健康写入数据。")
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Energy / body / activity sections

struct HealthKitImportBar: View {
    @Bindable var viewModel: TodayMealsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await viewModel.importFromHealthKit(overwriteManual: false) }
            } label: {
                if viewModel.isImportingHealthKit {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("从健康导入", systemImage: "heart")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isImportingHealthKit || viewModel.isMutating)
            .accessibilityLabel("从 Apple 健康导入所选日期数据")

            if let status = viewModel.healthKitStatusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Compact day overview: small rings + metric grid + thin nutrient bars.
/// Intended height ~220–320pt so body/activity remain visible on first screen.
struct DayEnergySummaryCard: View {
    let energy: DayEnergySummary
    var progress: GoalsProgress = GoalsProgress(
        intakeKcal: 0,
        netKcal: 0,
        proteinG: 0,
        carbsG: 0,
        fiberG: 0,
        goals: .empty
    )

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("当日总览")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if progress.goals.hasAnyGoal {
                    Text("含目标")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Row 1: compact calorie rings
            HStack(spacing: 10) {
                DashboardRingView(
                    title: "摄入",
                    valueText: formatKcal(energy.foodIntakeKcal),
                    subtitle: progress.goals.hasCalorieGoal
                        ? "/ \(formatKcal(progress.goals.dailyCaloriesKcal ?? 0))"
                        : "kcal",
                    progress: progress.goals.hasCalorieGoal ? progress.intakeProgress : 0,
                    tint: progress.isOverGoal(current: progress.intakeKcal, goal: progress.goals.dailyCaloriesKcal)
                        ? .orange
                        : .accentColor,
                    showTrackOnly: !progress.goals.hasCalorieGoal,
                    size: 68,
                    lineWidth: 6
                )
                DashboardRingView(
                    title: "净热量",
                    valueText: formatKcal(energy.netKcal),
                    subtitle: progress.goals.hasCalorieGoal
                        ? "/ \(formatKcal(progress.goals.dailyCaloriesKcal ?? 0))"
                        : "kcal",
                    progress: progress.goals.hasCalorieGoal ? progress.netProgress : 0,
                    tint: .green,
                    showTrackOnly: !progress.goals.hasCalorieGoal,
                    size: 68,
                    lineWidth: 6
                )
            }
            .frame(maxWidth: .infinity)

            // Row 2: metric grid
            LazyVGrid(columns: gridColumns, spacing: 6) {
                compactMetric(title: "活动消耗", value: "\(formatKcal(energy.activityBurnKcal)) kcal")
                compactMetric(title: "运动消耗", value: "\(formatKcal(energy.exerciseBurnKcal)) kcal")
                compactMetric(title: "步数", value: energy.steps > 0 ? formatNumber(energy.steps) : "—")
                compactMetric(title: "体重", value: weightValueText)
            }

            // Row 3: compact nutrient bars — protein / carbs / fiber
            if progress.goals.proteinGrams != nil
                || progress.goals.carbsGrams != nil
                || progress.goals.fiberGrams != nil
                || progress.proteinG > 0
                || progress.carbsG > 0
                || progress.fiberG > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    macroBar(
                        title: "蛋白质",
                        line: progress.proteinLine,
                        progress: progress.goals.proteinGrams != nil ? progress.proteinProgress : 0,
                        tint: .blue,
                        showTrackOnly: progress.goals.proteinGrams == nil
                    )
                    macroBar(
                        title: "碳水",
                        line: progress.carbsLine,
                        progress: progress.goals.carbsGrams != nil ? progress.carbsProgress : 0,
                        tint: .orange,
                        showTrackOnly: progress.goals.carbsGrams == nil
                    )
                    macroBar(
                        title: "膳食纤维",
                        line: progress.fiberLine,
                        progress: progress.goals.fiberGrams != nil ? progress.fiberProgress : 0,
                        tint: .purple,
                        showTrackOnly: progress.goals.fiberGrams == nil
                    )
                }
            }

            Text(netFormulaCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当日总览")
    }

    private var netFormulaCaption: String {
        if energy.dailyActivitySource == "healthkit" {
            return "净热量 = 摄入 − 活动（健康 active energy 已含 workout）"
        }
        return "净热量 = 摄入 − 活动 − 运动"
    }

    private var weightValueText: String {
        let current = energy.weightKg.flatMap { $0 > 0 ? formatNumber($0) : nil }
        if let target = progress.goals.targetWeightKg, target > 0 {
            if let current {
                return "\(current)/\(formatNumber(target)) kg"
            }
            return "目标 \(formatNumber(target)) kg"
        }
        return current.map { "\($0) kg" } ?? "—"
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.55))
        )
    }

    private func macroBar(
        title: String,
        line: String,
        progress: Double,
        tint: Color,
        showTrackOnly: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(line)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(tint.opacity(showTrackOnly ? 0.25 : 1))
                        .frame(width: showTrackOnly ? 0 : geo.size.width * progress)
                }
            }
            .frame(height: 4)
        }
    }

    private func formatKcal(_ value: Double) -> String {
        formatNumber(value)
    }

    private func formatNumber(_ value: Double) -> String {
        if !value.isFinite { return "0" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}

/// Compact circular progress ring (0...1). Default size is small for home overview.
struct DashboardRingView: View {
    let title: String
    let valueText: String
    let subtitle: String
    let progress: Double
    var tint: Color = .accentColor
    /// When true, only show empty track (no goal set).
    var showTrackOnly: Bool = false
    var size: CGFloat = 68
    var lineWidth: CGFloat = 6

    /// Always `0...1` for ring stroke.
    private var clamped: Double {
        let value = progress.isFinite ? progress : 0
        return min(1, max(0, value))
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: showTrackOnly ? 0 : clamped)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(valueText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(4)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("\(title) \(valueText) \(subtitle)")

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BodyMetricSection: View {
    @Bindable var viewModel: TodayMealsViewModel

    var body: some View {
        Section {
            if let body = viewModel.bodyMetric {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("体重", value: "\(format(body.weightKg)) kg")
                    if body.bodyFatPercent > 0 {
                        LabeledContent("体脂", value: "\(format(body.bodyFatPercent)) %")
                    }
                    if !body.note.isEmpty {
                        Text(body.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("编辑") { viewModel.openBodySheet() }
                Button("删除", role: .destructive) {
                    Task { await viewModel.deleteBodyMetric() }
                }
                .disabled(viewModel.isMutating)
            } else {
                Text("还没有体重记录，可手动添加或从健康导入。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("添加体重") { viewModel.openBodySheet() }
            }
        } header: {
            sectionHeader("身体数据", systemImage: "scalemass")
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct DailyActivitySection: View {
    @Bindable var viewModel: TodayMealsViewModel

    var body: some View {
        Section {
            if let day = viewModel.dailyActivity {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("步数", value: format(day.steps))
                    LabeledContent("活动热量", value: "\(format(day.activeCalories)) kcal")
                    if day.distanceKm > 0 {
                        LabeledContent("距离", value: "\(format(day.distanceKm)) km")
                    }
                    if !day.note.isEmpty {
                        Text(day.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("编辑") { viewModel.openActivitySheet() }
                Button("删除", role: .destructive) {
                    Task { await viewModel.deleteDailyActivity() }
                }
                .disabled(viewModel.isMutating)
            } else {
                Text("还没有每日活动记录，可手动添加或从健康导入。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("添加活动") { viewModel.openActivitySheet() }
            }
        } header: {
            sectionHeader("每日活动", systemImage: "figure.walk")
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct ExerciseSection: View {
    @Bindable var viewModel: TodayMealsViewModel

    var body: some View {
        Section {
            if viewModel.exercises.isEmpty {
                Text("还没有运动记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(exercise.title).font(.body.weight(.medium))
                            Spacer()
                            Text("\(format(exercise.activeCalories)) kcal")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text("\(exercise.type) · \(format(exercise.durationMinutes)) 分钟")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteExercise(exercise) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(viewModel.isMutating)
                    }
                }
            }
            Button {
                viewModel.openExerciseSheet()
            } label: {
                Label("添加运动", systemImage: "plus")
            }
        } header: {
            sectionHeader("运动记录", systemImage: "figure.run")
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct BodyMetricEditView: View {
    @Bindable var viewModel: TodayMealsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showMoreMetrics = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("当前日记日 \(viewModel.selectedDateKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("体重 kg", text: $viewModel.draftWeightKg)
                        .keyboardType(.decimalPad)
                    TextField("体脂 %（可选）", text: $viewModel.draftBodyFatPercent)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $viewModel.draftBodyNote)
                } header: {
                    Text("身体指标")
                }

                Section {
                    if let preview = viewModel.bodyDraftPhotoPreview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityLabel("已选截图预览")
                    }
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            viewModel.bodyDraftPhotoData == nil ? "选择体脂秤截图" : "更换截图",
                            systemImage: "photo"
                        )
                    }
                    .disabled(viewModel.isAnalyzingBody || viewModel.isPreparingBodyPhoto || viewModel.isMutating)
                    .onChange(of: pickerItem) { _, newItem in
                        guard let newItem else { return }
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self) {
                                await viewModel.setBodyDraftPhoto(rawData: data)
                            } else {
                                viewModel.reportUserFacingError("无法读取所选图片。")
                            }
                            pickerItem = nil
                        }
                    }

                    Button {
                        Task { await viewModel.runBodyAIAnalysis() }
                    } label: {
                        if viewModel.isAnalyzingBody || viewModel.isPreparingBodyPhoto {
                            HStack {
                                ProgressView()
                                Text(viewModel.isPreparingBodyPhoto ? "处理图片…" : "AI 识别中…")
                            }
                        } else {
                            Label("AI 识别截图", systemImage: "sparkles")
                        }
                    }
                    .disabled(!viewModel.canRunBodyAIAnalysis)
                    .buttonStyle(.borderedProminent)

                    if viewModel.bodyDraftPhotoData != nil {
                        Button("清除截图", role: .destructive) {
                            viewModel.clearBodyDraftPhoto()
                        }
                        .disabled(viewModel.isAnalyzingBody)
                    }

                    if let hint = viewModel.bodyAnalysisDateHint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if viewModel.showBodyLowConfidenceWarning {
                        Text("识别置信度较低，请仔细核对数值后再保存。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if let notes = viewModel.bodyAnalysisNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("截图 AI")
                } footer: {
                    Text("截图仅用于识别，不会上传到照片库或永久存储。")
                        .font(.caption2)
                }

                DisclosureGroup("更多指标", isExpanded: $showMoreMetrics) {
                    TextField("BMI", text: $viewModel.draftBmi)
                        .keyboardType(.decimalPad)
                    TextField("肌肉量 kg", text: $viewModel.draftMuscleKg)
                        .keyboardType(.decimalPad)
                    TextField("骨量 kg", text: $viewModel.draftBoneMassKg)
                        .keyboardType(.decimalPad)
                    TextField("水分 %", text: $viewModel.draftWaterPercent)
                        .keyboardType(.decimalPad)
                    TextField("基础代谢 kcal", text: $viewModel.draftBmrKcal)
                        .keyboardType(.decimalPad)
                    TextField("内脏脂肪", text: $viewModel.draftVisceralFat)
                        .keyboardType(.decimalPad)
                }

                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("身体数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelBodySheet()
                        dismiss()
                    }
                    .disabled(viewModel.isAnalyzingBody || viewModel.isMutating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await viewModel.saveBodyMetric()
                            if !viewModel.isPresentingBodySheet { dismiss() }
                        }
                    }
                    .disabled(viewModel.isMutating || viewModel.isAnalyzingBody)
                }
            }
        }
    }
}

struct DailyActivityEditView: View {
    @Bindable var viewModel: TodayMealsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("每日活动 · \(viewModel.selectedDateKey)") {
                    TextField("步数", text: $viewModel.draftSteps)
                        .keyboardType(.numberPad)
                    TextField("活动热量 kcal", text: $viewModel.draftActiveCalories)
                        .keyboardType(.decimalPad)
                    TextField("距离 km（可选）", text: $viewModel.draftDistanceKm)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $viewModel.draftActivityNote)
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("每日活动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelActivitySheet()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await viewModel.saveDailyActivity()
                            if !viewModel.isPresentingActivitySheet { dismiss() }
                        }
                    }
                    .disabled(viewModel.isMutating)
                }
            }
        }
    }
}

struct ExerciseEditView: View {
    @Bindable var viewModel: TodayMealsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("运动 · \(viewModel.selectedDateKey)") {
                    TextField("类型", text: $viewModel.draftExerciseType)
                    TextField("标题（可选）", text: $viewModel.draftExerciseTitle)
                    TextField("时长 分钟", text: $viewModel.draftExerciseDuration)
                        .keyboardType(.decimalPad)
                    TextField("消耗 kcal", text: $viewModel.draftExerciseCalories)
                        .keyboardType(.decimalPad)
                    TextField("距离 km（可选）", text: $viewModel.draftExerciseDistance)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $viewModel.draftExerciseNote)
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("添加运动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelExerciseSheet()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await viewModel.saveExercise()
                            if !viewModel.isPresentingExerciseSheet { dismiss() }
                        }
                    }
                    .disabled(viewModel.isMutating)
                }
            }
        }
    }
}

/// Date navigation: previous / next / label / today / DatePicker.
struct DiaryDateBar: View {
    @Bindable var viewModel: TodayMealsViewModel

    private var dateControlsDisabled: Bool {
        viewModel.isPresentingAddSheet
            || viewModel.isPresentingBodySheet
            || viewModel.isPresentingActivitySheet
            || viewModel.isPresentingExerciseSheet
            || viewModel.isAnalyzing
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.goToPreviousDay() }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("前一天")
                .disabled(dateControlsDisabled)

                Spacer(minLength: 4)

                VStack(spacing: 2) {
                    Text(viewModel.displayTitle)
                        .font(.headline)
                    Text(viewModel.selectedDateKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }

                Spacer(minLength: 4)

                Button {
                    Task { await viewModel.goToNextDay() }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("后一天")
                .disabled(dateControlsDisabled)
            }

            HStack(spacing: 12) {
                Button("今天") {
                    Task { await viewModel.goToToday() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isToday || dateControlsDisabled)

                DatePicker(
                    "选择日期",
                    selection: Binding(
                        get: { viewModel.selectedDate },
                        set: { newValue in
                            Task { await viewModel.selectDate(newValue) }
                        }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .disabled(dateControlsDisabled)
            }
        }
        .padding(.horizontal, 4)
    }
}

@ViewBuilder
private func sectionHeader(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
        .foregroundStyle(.primary)
}

struct DailySummaryCard: View {
    let summary: DailyNutritionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricRow(title: "总热量", value: "\(format(summary.calories)) kcal")
            HStack {
                metricChip(title: "蛋白", value: "\(format(summary.protein)) g")
                metricChip(title: "碳水", value: "\(format(summary.carbs)) g")
                metricChip(title: "脂肪", value: "\(format(summary.fat)) g")
            }
            if summary.fiber > 0 || summary.grams > 0 {
                Text("纤维 \(format(summary.fiber)) g · 重量 \(format(summary.grams)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct MealSectionView: View {
    let group: MealGroup
    let isMutating: Bool
    let onAdd: () -> Void
    var onEdit: (FoodItem) -> Void = { _ in }
    var onAddToFavorites: (FoodItem) -> Void = { _ in }
    let onDelete: (FoodItem) -> Void

    var body: some View {
        Section {
            if group.items.isEmpty {
                Text("暂无")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(group.items) { item in
                    Button {
                        onEdit(item)
                    } label: {
                        FoodItemRowView(item: item)
                    }
                    .buttonStyle(.plain)
                    .disabled(isMutating)
                    .accessibilityLabel("编辑 \(item.name)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(isMutating)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            onEdit(item)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.accentColor)
                        .disabled(isMutating)
                        Button {
                            onAddToFavorites(item)
                        } label: {
                            Label("加入常吃", systemImage: "star")
                        }
                        .tint(.orange)
                        .disabled(isMutating)
                    }
                    .contextMenu {
                        Button {
                            onEdit(item)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button {
                            onAddToFavorites(item)
                        } label: {
                            Label("加入常吃", systemImage: "star")
                        }
                        Button(role: .destructive) {
                            onDelete(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(group.meal.titleZh)
                Spacer()
                if !group.items.isEmpty {
                    Text("\(format(group.summary.calories)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("添加\(group.meal.titleZh)")
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - Favorite foods

struct FavoriteFoodsSection: View {
    @Bindable var viewModel: TodayMealsViewModel

    var body: some View {
        Section {
            if viewModel.favoriteFoods.isEmpty {
                HStack {
                    Text("暂无常吃模板")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("管理") {
                        viewModel.openFavoritesManageSheet()
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.borderless)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.favoriteFoods) { favorite in
                            Button {
                                Task { await viewModel.quickAddFavorite(favorite) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(favorite.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(favorite.meal.titleZh) · \(formatKcal(favorite.calories)) kcal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isMutating)
                            .accessibilityLabel("快捷添加 \(favorite.name)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        } header: {
            HStack {
                Text("常吃")
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                    .foregroundStyle(.primary)
                Spacer()
                Button("管理") {
                    viewModel.openFavoritesManageSheet()
                }
                .font(.caption.weight(.medium))
                .textCase(nil)
            }
        } footer: {
            Text("点模板即记入 \(viewModel.selectedDateKey)，使用模板默认餐次；不复制照片。")
                .font(.caption2)
        }
    }

    private func formatKcal(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct FavoriteFoodsManageView: View {
    @Bindable var viewModel: TodayMealsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.beginAddFavoriteTemplate()
                        isPresentingEditor = true
                    } label: {
                        Label("新增常吃", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    if viewModel.favoriteFoods.isEmpty {
                        Text("还没有常吃模板。可从饮食记录左滑「加入常吃」，或点上方新增。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.favoriteFoods) { favorite in
                            Button {
                                viewModel.beginEditFavoriteTemplate(favorite)
                                isPresentingEditor = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(favorite.name)
                                        .foregroundStyle(.primary)
                                    Text("\(favorite.meal.titleZh) · \(format(favorite.calories)) kcal · \(format(favorite.grams)) g")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteFavoriteTemplate(id: favorite.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("模板列表")
                } footer: {
                    Text("模板仅保存在本机。编辑模板不会修改已有饮食记录。")
                }
            }
            .navigationTitle("管理常吃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                FavoriteFoodEditorView(viewModel: viewModel) {
                    isPresentingEditor = false
                }
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct FavoriteFoodEditorView: View {
    @Bindable var viewModel: TodayMealsViewModel
    let onDone: () -> Void

    private var isEditing: Bool { viewModel.editingFavoriteId != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名称", text: $viewModel.favoriteDraftName)
                    Picker("默认餐次", selection: $viewModel.favoriteDraftMeal) {
                        ForEach(MealType.displayOrder, id: \.self) { meal in
                            Text(meal.titleZh).tag(meal)
                        }
                    }
                    TextField("份量 (g)", text: $viewModel.favoriteDraftGrams)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $viewModel.favoriteDraftNote)
                }

                Section("营养") {
                    TextField("热量 (kcal)", text: $viewModel.favoriteDraftCalories)
                        .keyboardType(.decimalPad)
                    TextField("蛋白质 (g)", text: $viewModel.favoriteDraftProtein)
                        .keyboardType(.decimalPad)
                    TextField("碳水 (g)", text: $viewModel.favoriteDraftCarbs)
                        .keyboardType(.decimalPad)
                    TextField("脂肪 (g)", text: $viewModel.favoriteDraftFat)
                        .keyboardType(.decimalPad)
                    TextField("膳食纤维 (g)", text: $viewModel.favoriteDraftFiber)
                        .keyboardType(.decimalPad)
                }

                if let error = viewModel.favoriteFormError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑常吃" : "新增常吃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onDone()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if viewModel.saveFavoriteTemplate() {
                            onDone()
                        }
                    }
                }
            }
        }
    }
}

struct FoodItemRowView: View {
    let item: FoodItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("\(format(item.calories)) kcal")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if item.protein > 0 {
                        Text("P \(format(item.protein))g")
                    }
                    if item.carbs > 0 {
                        Text("C \(format(item.carbs))g")
                    }
                    if item.fat > 0 {
                        Text("F \(format(item.fat))g")
                    }
                    if item.grams > 0 {
                        Text("\(format(item.grams))g")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let urlString = item.photoURLs.first ?? item.photoPaths.first
        if let urlString, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    photoPlaceholder
                case .empty:
                    ProgressView()
                @unknown default:
                    photoPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if !item.photoPaths.isEmpty {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.secondarySystemFill))
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct AddFoodItemView: View {
    @Bindable var viewModel: TodayMealsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $viewModel.draftName)
                    Picker("餐次", selection: $viewModel.draftMeal) {
                        ForEach(MealType.displayOrder, id: \.self) { meal in
                            Text(meal.titleZh).tag(meal)
                        }
                    }
                    if viewModel.isEditingFood {
                        DatePicker(
                            "日期",
                            selection: $viewModel.draftDate,
                            displayedComponents: .date
                        )
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    }
                    TextField("热量 kcal", text: $viewModel.draftCalories)
                        .keyboardType(.decimalPad)
                }

                if !viewModel.isEditingFood {
                    Section {
                        Text("写备注或选照片后分析。结果只填入表单，需你确认后保存。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await viewModel.runAIAnalysis() }
                        } label: {
                            if viewModel.isAnalyzing {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("AI 分析餐食", systemImage: "sparkles")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canRunAIAnalysis)
                        if let summary = viewModel.analysisSummary {
                            Text(summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Label("AI 分析", systemImage: "sparkles")
                    }

                    Section("照片（可选）") {
                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Label(
                                viewModel.draftPhotoPreview == nil ? "从相册选择" : "重新选择",
                                systemImage: "photo.on.rectangle"
                            )
                        }
                        .onChange(of: pickerItem) { _, newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    await viewModel.setDraftPhoto(rawData: data)
                                } else {
                                    viewModel.reportUserFacingError("无法读取所选图片。")
                                }
                            }
                        }

                        if viewModel.isPreparingPhoto {
                            ProgressView("正在处理图片…")
                        }

                        if let preview = viewModel.draftPhotoPreview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            Button("移除照片", role: .destructive) {
                                viewModel.clearDraftPhoto()
                                pickerItem = nil
                            }
                        }

                        Text("照片将上传到私有 meal-photos，路径为当前用户目录；列表通过 signed URL 显示。AI 分析使用本地压缩图，不发送 signed URL。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !viewModel.editingPhotoPaths.isEmpty {
                    Section("照片") {
                        editModePhotoThumbnail
                        Text("编辑时保留原照片，暂不支持更换或删除。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("营养（可选）") {
                    TextField("蛋白质 g", text: $viewModel.draftProtein)
                        .keyboardType(.decimalPad)
                    TextField("碳水 g", text: $viewModel.draftCarbs)
                        .keyboardType(.decimalPad)
                    TextField("脂肪 g", text: $viewModel.draftFat)
                        .keyboardType(.decimalPad)
                    TextField("膳食纤维 g", text: $viewModel.draftFiber)
                        .keyboardType(.decimalPad)
                    TextField("份量 g", text: $viewModel.draftGrams)
                        .keyboardType(.decimalPad)
                    TextField(
                        viewModel.isEditingFood ? "备注" : "备注 / AI 文字说明",
                        text: $viewModel.draftNote,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 5)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(viewModel.foodFormNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelAdd()
                        dismiss()
                    }
                    .disabled(viewModel.isMutating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isMutating {
                        ProgressView()
                    } else {
                        Button("保存") {
                            Task {
                                await viewModel.saveFoodItem()
                                if !viewModel.isPresentingAddSheet {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(
                            viewModel.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || viewModel.isPreparingPhoto
                                || viewModel.isAnalyzing
                        )
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isAnalyzing || viewModel.isMutating)
        }
    }

    @ViewBuilder
    private var editModePhotoThumbnail: some View {
        let urlString = viewModel.editingPhotoDisplayURLs.first
        if let urlString, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    photoPlaceholder
                @unknown default:
                    photoPlaceholder
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } else {
            photoPlaceholder
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.secondarySystemFill))
            .frame(height: 120)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}
