import PhotosUI
import SwiftUI

struct TodayMealsView: View {
    @Bindable var viewModel: TodayMealsViewModel
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Text(viewModel.user.redactedEmail)
                            Button("退出登录", role: .destructive, action: onSignOut)
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.openAddSheet()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("新增食物")
                        .disabled(viewModel.isPresentingAddSheet)
                    }
                }
                .sheet(isPresented: $viewModel.isPresentingAddSheet) {
                    AddFoodItemView(viewModel: viewModel)
                        .interactiveDismissDisabled(viewModel.isAnalyzing || viewModel.isMutating)
                }
                .sheet(isPresented: $viewModel.isPresentingBodySheet) {
                    BodyMetricEditView(viewModel: viewModel)
                }
                .sheet(isPresented: $viewModel.isPresentingActivitySheet) {
                    DailyActivityEditView(viewModel: viewModel)
                }
                .sheet(isPresented: $viewModel.isPresentingExerciseSheet) {
                    ExerciseEditView(viewModel: viewModel)
                }
                .task {
                    await viewModel.load()
                }
                .refreshable {
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

            // Pinned below date bar so it is always visible (not buried in List).
            VStack(alignment: .leading, spacing: 8) {
                DayEnergySummaryCard(energy: viewModel.dayEnergySummary)
                HealthKitImportBar(viewModel: viewModel)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color(.systemBackground))
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

            Group {
                switch viewModel.loadState {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载 \(viewModel.displayTitle) 的饮食…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                case .error(let message):
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await viewModel.load() }
                        }
                    }
                case .empty, .loaded:
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.displayTitle)
                                    .font(.headline)
                                Text(viewModel.selectedDateKey)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                                if !viewModel.isToday {
                                    Text("补记将保存到该日期")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if viewModel.summary.calories > 0
                            || viewModel.summary.protein > 0
                            || viewModel.summary.carbs > 0
                            || viewModel.summary.fat > 0 {
                            Section("饮食营养") {
                                DailySummaryCard(summary: viewModel.summary)
                            }
                        }

                        BodyMetricSection(viewModel: viewModel)
                        DailyActivitySection(viewModel: viewModel)
                        ExerciseSection(viewModel: viewModel)

                        if case .empty = viewModel.loadState {
                            Section {
                                ContentUnavailableView(
                                    "还没有饮食记录",
                                    systemImage: "fork.knife",
                                    description: Text(
                                        viewModel.isToday
                                            ? "点击右上角 + 手动添加今日食物，可附带照片。"
                                            : "点击右上角 + 为 \(viewModel.displayTitle) 补记食物。"
                                    )
                                )
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                            }
                        }

                        ForEach(viewModel.mealSections, id: \.meal) { section in
                            MealSectionView(
                                group: section,
                                isMutating: viewModel.isMutating,
                                onAdd: { viewModel.openAddSheet(defaultMeal: section.meal) },
                                onDelete: { item in
                                    Task { await viewModel.deleteItem(item) }
                                }
                            )
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
                }
            }
        }
    }
}

// MARK: - Energy / body / activity sections

struct HealthKitImportBar: View {
    @Bindable var viewModel: TodayMealsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await viewModel.importFromHealthKit(overwriteManual: false) }
            } label: {
                if viewModel.isImportingHealthKit {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("从健康导入", systemImage: "heart.text.square")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isImportingHealthKit || viewModel.isMutating)
            .accessibilityLabel("从 Apple 健康导入所选日期数据")

            Text("只读导入所选日期的步数、活动、距离、体重与运动；不会写入健康。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let status = viewModel.healthKitStatusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Minimal day overview pinned under the date bar (no ring charts).
struct DayEnergySummaryCard: View {
    let energy: DayEnergySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当日总览")
                .font(.headline)

            VStack(spacing: 6) {
                metric("摄入", "\(formatKcal(energy.foodIntakeKcal)) kcal")
                metric("活动消耗", "\(formatKcal(energy.activityBurnKcal)) kcal")
                metric("运动消耗", "\(formatKcal(energy.exerciseBurnKcal)) kcal")
                metric("净热量", "\(formatKcal(energy.netKcal)) kcal")
                    .fontWeight(.semibold)
                metric("步数", energy.steps > 0 ? formatNumber(energy.steps) : "—")
                metric(
                    "体重",
                    energy.weightKg.map { $0 > 0 ? "\(formatNumber($0)) kg" : "—" } ?? "—"
                )
            }

            if energy.dailyActivitySource == "healthkit" {
                Text("净热量 = 摄入 − 活动消耗（健康 active energy 已含 workout，不重复扣运动）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("净热量 = 摄入 − 活动消耗 − 运动消耗")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当日总览")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
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
                Text("暂无身体数据").foregroundStyle(.secondary)
                Button("添加体重") { viewModel.openBodySheet() }
            }
        } header: {
            Text("身体数据")
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
                Text("暂无每日活动").foregroundStyle(.secondary)
                Button("添加活动") { viewModel.openActivitySheet() }
            }
        } header: {
            Text("每日活动")
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
                Text("暂无运动记录").foregroundStyle(.secondary)
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
            Text("运动记录")
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct BodyMetricEditView: View {
    @Bindable var viewModel: TodayMealsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("身体指标 · \(viewModel.selectedDateKey)") {
                    TextField("体重 kg", text: $viewModel.draftWeightKg)
                        .keyboardType(.decimalPad)
                    TextField("体脂 %（可选）", text: $viewModel.draftBodyFatPercent)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $viewModel.draftBodyNote)
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await viewModel.saveBodyMetric()
                            if !viewModel.isPresentingBodySheet { dismiss() }
                        }
                    }
                    .disabled(viewModel.isMutating)
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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.goToPreviousDay() }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("前一天")
                .disabled(viewModel.isPresentingAddSheet || viewModel.isPresentingBodySheet || viewModel.isPresentingActivitySheet || viewModel.isPresentingExerciseSheet || viewModel.isAnalyzing)

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
                }
                .accessibilityLabel("后一天")
                .disabled(viewModel.isPresentingAddSheet || viewModel.isPresentingBodySheet || viewModel.isPresentingActivitySheet || viewModel.isPresentingExerciseSheet || viewModel.isAnalyzing)
            }

            HStack(spacing: 12) {
                Button("今天") {
                    Task { await viewModel.goToToday() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isToday || viewModel.isPresentingAddSheet || viewModel.isPresentingBodySheet || viewModel.isPresentingActivitySheet || viewModel.isPresentingExerciseSheet || viewModel.isAnalyzing)

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
                .disabled(viewModel.isPresentingAddSheet || viewModel.isPresentingBodySheet || viewModel.isPresentingActivitySheet || viewModel.isPresentingExerciseSheet || viewModel.isAnalyzing)
            }
        }
    }
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
    let onDelete: (FoodItem) -> Void

    var body: some View {
        Section {
            if group.items.isEmpty {
                Text("暂无")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(group.items) { item in
                    FoodItemRowView(item: item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDelete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .disabled(isMutating)
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
                    TextField("热量 kcal", text: $viewModel.draftCalories)
                        .keyboardType(.decimalPad)
                }

                Section("AI 分析（可选）") {
                    Text("在备注中写描述（如「一碗牛肉饭」），或先选照片，再点分析。结果只填入表单，需你确认后保存。")
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
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!viewModel.canRunAIAnalysis)
                    if let summary = viewModel.analysisSummary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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

                Section("营养（可选）") {
                    TextField("蛋白质 g", text: $viewModel.draftProtein)
                        .keyboardType(.decimalPad)
                    TextField("碳水 g", text: $viewModel.draftCarbs)
                        .keyboardType(.decimalPad)
                    TextField("脂肪 g", text: $viewModel.draftFat)
                        .keyboardType(.decimalPad)
                    TextField("重量 g", text: $viewModel.draftGrams)
                        .keyboardType(.decimalPad)
                    TextField("备注 / AI 文字说明", text: $viewModel.draftNote, axis: .vertical)
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
            .navigationTitle("新增食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelAdd()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isMutating {
                        ProgressView()
                    } else {
                        Button("保存") {
                            Task {
                                await viewModel.saveNewItem()
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
        }
    }
}
