import SwiftUI

struct TodayMealsView: View {
    @Bindable var viewModel: TodayMealsViewModel
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("今日饮食")
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
                    }
                }
                .sheet(isPresented: $viewModel.isPresentingAddSheet) {
                    AddFoodItemView(viewModel: viewModel)
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
        switch viewModel.loadState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在加载今日饮食…")
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
                        Text("今天")
                            .font(.headline)
                        Text(viewModel.dateKey)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                    .padding(.vertical, 4)
                }

                Section("今日汇总") {
                    DailySummaryCard(summary: viewModel.summary)
                }

                if case .empty = viewModel.loadState {
                    Section {
                        ContentUnavailableView(
                            "还没有记录",
                            systemImage: "fork.knife",
                            description: Text("点击右上角 + 手动添加今日食物。")
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
        .padding(.vertical, 2)
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct AddFoodItemView: View {
    @Bindable var viewModel: TodayMealsViewModel
    @Environment(\.dismiss) private var dismiss

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

                Section("营养（可选）") {
                    TextField("蛋白质 g", text: $viewModel.draftProtein)
                        .keyboardType(.decimalPad)
                    TextField("碳水 g", text: $viewModel.draftCarbs)
                        .keyboardType(.decimalPad)
                    TextField("脂肪 g", text: $viewModel.draftFat)
                        .keyboardType(.decimalPad)
                    TextField("重量 g", text: $viewModel.draftGrams)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $viewModel.draftNote)
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
                        .disabled(viewModel.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
