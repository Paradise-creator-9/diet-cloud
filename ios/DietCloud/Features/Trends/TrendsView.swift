import Charts
import SwiftUI

struct TrendsView: View {
    @Bindable var viewModel: TrendsViewModel
    private let diaryCalendar = DiaryCalendar()

    var body: some View {
        content
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView("正在加载趋势…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        case .error(let message):
            ContentUnavailableView {
                Label("无法加载趋势", systemImage: "chart.xyaxis.line")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("重试加载趋势")
            }
            .background(Color(.systemGroupedBackground))
        case .empty(let snapshot):
            List {
                rangePicker
                emptyBanner
                summarySection(snapshot)
            }
            .listStyle(.insetGrouped)
        case .loaded(let snapshot):
            trendsList(snapshot: snapshot, banner: nil)
        case .partial(let snapshot, let failedSources, let message):
            trendsList(
                snapshot: snapshot,
                banner: message,
                failedSources: failedSources
            )
        }
    }

    private var rangePicker: some View {
        Section {
            Picker("范围", selection: Binding(
                get: { viewModel.range },
                set: { newValue in
                    Task { await viewModel.selectRange(newValue) }
                }
            )) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityLabel("趋势时间范围")
        }
    }

    private var emptyBanner: some View {
        Section {
            Text("该周期内还没有饮食、身体或活动记录。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func trendsList(
        snapshot: TrendSnapshot,
        banner: String?,
        failedSources: [String] = []
    ) -> some View {
        List {
            rangePicker
            if let banner {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(banner, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if !failedSources.isEmpty {
                            Text("失败数据源：\(failedSources.joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("重试") {
                            Task { await viewModel.retry() }
                        }
                        .font(.footnote.weight(.semibold))
                        .accessibilityLabel("重试加载失败的数据源")
                    }
                }
            }
            summarySection(snapshot)
            calorieSection(snapshot)
            nutrientSection(snapshot)
            weightSection(snapshot)
            activitySection(snapshot)
        }
        .listStyle(.insetGrouped)
    }

    private func summarySection(_ snapshot: TrendSnapshot) -> some View {
        let s = snapshot.summary
        return Section("周期摘要") {
            LabeledContent("有饮食记录", value: "\(s.foodRecordedDays) 天")
            LabeledContent("平均每日摄入") {
                Text(averageIntakeText(s.averageIntakeKcal))
                    .font(.body)
                    .monospacedDigit()
            }
            LabeledContent("综合达标") {
                Text(goalMetText(s.goalMet))
                    .font(.body)
                    .monospacedDigit()
            }
            LabeledContent("运动次数", value: "\(s.exerciseSessionCount) 次")
            LabeledContent("运动总时长") {
                Text(formatMinutes(s.exerciseTotalMinutes))
                    .font(.body)
                    .monospacedDigit()
            }
        }
    }

    private func calorieSection(_ snapshot: TrendSnapshot) -> some View {
        let points = snapshot.intakePoints()
        return Section("热量趋势") {
            if points.isEmpty {
                Text("暂无饮食热量数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        if let date = chartDate(point.dateKey) {
                            BarMark(
                                x: .value("日期", date, unit: .day),
                                y: .value("摄入", point.value)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                        }
                    }
                    if let goal = snapshot.calorieGoalKcal, goal > 0 {
                        RuleMark(y: .value("目标", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("目标 \(formatNumber(goal))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(minHeight: 160, idealHeight: 180)
                .chartYAxisLabel("kcal")
                .chartXAxis { xAxis(for: snapshot.range) }
                .accessibilityLabel("每日热量摄入柱状图")
            }
        }
    }

    private func nutrientSection(_ snapshot: TrendSnapshot) -> some View {
        let points = snapshot.nutrientPoints(viewModel.selectedNutrient)
        return Section("营养趋势") {
            Picker("营养", selection: Binding(
                get: { viewModel.selectedNutrient },
                set: { viewModel.selectNutrient($0) }
            )) {
                ForEach(TrendNutrientMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("营养指标")

            if points.isEmpty {
                Text("暂无\(viewModel.selectedNutrient.title)数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        if let date = chartDate(point.dateKey) {
                            LineMark(
                                x: .value("日期", date, unit: .day),
                                y: .value(viewModel.selectedNutrient.title, point.value)
                            )
                            .interpolationMethod(points.count >= 3 ? .catmullRom : .linear)
                            PointMark(
                                x: .value("日期", date, unit: .day),
                                y: .value(viewModel.selectedNutrient.title, point.value)
                            )
                        }
                    }
                }
                .frame(minHeight: 140, idealHeight: 160)
                .chartYAxisLabel("g")
                .chartXAxis { xAxis(for: snapshot.range) }
                .accessibilityLabel("\(viewModel.selectedNutrient.title)趋势图")
            }
        }
    }

    private func weightSection(_ snapshot: TrendSnapshot) -> some View {
        let points = snapshot.weightPoints()
        return Section("体重趋势") {
            if points.isEmpty {
                Text("暂无体重记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        if let date = chartDate(point.dateKey) {
                            LineMark(
                                x: .value("日期", date, unit: .day),
                                y: .value("体重", point.value)
                            )
                            .interpolationMethod(points.count >= 3 ? .catmullRom : .linear)
                            PointMark(
                                x: .value("日期", date, unit: .day),
                                y: .value("体重", point.value)
                            )
                        }
                    }
                }
                .frame(minHeight: 140, idealHeight: 160)
                .chartYAxisLabel("kg")
                .chartXAxis { xAxis(for: snapshot.range) }
                .accessibilityLabel("体重趋势图")
            }
        }
    }

    private func activitySection(_ snapshot: TrendSnapshot) -> some View {
        let points = snapshot.activityPoints(viewModel.selectedActivityMetric)
        return Section("活动趋势") {
            Picker("活动", selection: Binding(
                get: { viewModel.selectedActivityMetric },
                set: { viewModel.selectActivityMetric($0) }
            )) {
                ForEach(TrendActivityMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("活动指标")

            if points.isEmpty {
                Text("暂无每日活动数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        if let date = chartDate(point.dateKey) {
                            BarMark(
                                x: .value("日期", date, unit: .day),
                                y: .value(viewModel.selectedActivityMetric.title, point.value)
                            )
                            .foregroundStyle(Color.green.gradient)
                        }
                    }
                }
                .frame(minHeight: 140, idealHeight: 160)
                .chartYAxisLabel(viewModel.selectedActivityMetric == .steps ? "步" : "kcal")
                .chartXAxis { xAxis(for: snapshot.range) }
                .accessibilityLabel("\(viewModel.selectedActivityMetric.title)趋势图")
            }

            Text("活动消耗来自每日活动记录，不叠加运动列表，避免与健康 active energy 重复计算。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Chart axis

    /// Sparse x labels for 30-day windows; denser (about daily) for 7-day.
    @AxisContentBuilder
    private func xAxis(for range: TrendRange) -> some AxisContent {
        let desired = range == .days30 ? 5 : 7
        AxisMarks(values: .automatic(desiredCount: desired)) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                .font(.caption2)
        }
    }

    private func chartDate(_ dateKey: String) -> Date? {
        diaryCalendar.date(fromDateKey: dateKey)
    }

    // MARK: - Formatting

    private func goalMetText(_ status: TrendGoalMetStatus) -> String {
        switch status {
        case .notConfigured:
            return "未设置目标"
        case .configured(let metDays):
            return "\(metDays) 天"
        }
    }

    private func averageIntakeText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(formatNumber(value)) kcal"
    }

    private func formatMinutes(_ value: Double) -> String {
        if !value.isFinite { return "0 分钟" }
        if value.rounded() == value {
            return "\(Int(value)) 分钟"
        }
        return String(format: "%.0f 分钟", value)
    }

    private func formatNumber(_ value: Double) -> String {
        if !value.isFinite { return "0" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
