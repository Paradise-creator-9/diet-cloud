import SwiftUI

struct PhotoLibraryView: View {
    @Bindable var viewModel: PhotoLibraryViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        content
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                rangePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
            }
            .sheet(isPresented: $viewModel.isPresentingDetail, onDismiss: {
                viewModel.closeDetail()
            }) {
                // Read selectedItem from viewModel so retrySign URL updates refresh the sheet.
                if let item = viewModel.selectedItem {
                    PhotoLibraryDetailView(
                        item: item,
                        isRetrying: viewModel.retryingPath == item.path,
                        onRetry: {
                            Task { await viewModel.retrySign(for: item) }
                        }
                    )
                    .id(item.id + (item.signedURL ?? ""))
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.retry()
            }
    }

    private var rangePicker: some View {
        Picker("范围", selection: Binding(
            get: { viewModel.range },
            set: { newValue in
                Task { await viewModel.selectRange(newValue) }
            }
        )) {
            ForEach(PhotoLibraryRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("照片库时间范围")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView("正在加载照片…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))

        case .error(let message):
            ContentUnavailableView {
                Label("无法加载", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
            }
            .background(Color(.systemGroupedBackground))

        case .empty:
            ContentUnavailableView(
                "还没有餐食照片",
                systemImage: "photo.on.rectangle.angled",
                description: Text("在饮食记录中添加带照片的食物后，会显示在这里。")
            )
            .background(Color(.systemGroupedBackground))

        case .loaded(let snap), .partial(let snap, _):
            grid(for: snap)
        }
    }

    @ViewBuilder
    private func grid(for snap: PhotoLibrarySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if case .partial(_, let message) = viewModel.loadState {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("重试") {
                            Task { await viewModel.retry() }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .padding(.horizontal)
                }

                if snap.wasCapped {
                    Text("仅显示最近 \(PhotoLibraryBuilder.maxPhotos) 张照片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(snap.sections) { section in
                        Section {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(section.items) { item in
                                    PhotoLibraryTile(
                                        item: item,
                                        isRetrying: viewModel.retryingPath == item.path,
                                        onTap: { viewModel.openDetail(item) },
                                        onRetry: {
                                            Task { await viewModel.retrySign(for: item) }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        } header: {
                            Text(section.dateKey)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .background(Color(.systemGroupedBackground).opacity(0.95))
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Tile

private struct PhotoLibraryTile: View {
    let item: PhotoLibraryItem
    let isRetrying: Bool
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let urlString = item.signedURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            failurePlaceholder
                        case .empty:
                            ProgressView()
                        @unknown default:
                            failurePlaceholder
                        }
                    }
                } else {
                    failurePlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(item.meal.titleZh)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name)，\(item.dateKey)")
        .contextMenu {
            if !item.hasDisplayURL {
                Button("重新加载", action: onRetry)
            }
        }
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 6) {
            if isRetrying {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button("重试", action: onRetry)
                    .font(.caption2.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemFill))
    }
}

// MARK: - Detail

struct PhotoLibraryDetailView: View {
    let item: PhotoLibraryItem
    let isRetrying: Bool
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photoBlock
                    foodInfo
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var photoBlock: some View {
        ZStack {
            if let urlString = item.signedURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure, .empty:
                        detailPlaceholder
                    @unknown default:
                        detailPlaceholder
                    }
                }
            } else {
                detailPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
    }

    private var detailPlaceholder: some View {
        VStack(spacing: 10) {
            if isRetrying {
                ProgressView("重新加载…")
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("无法显示照片")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("重试", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemFill))
        )
    }

    private var foodInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("名称", value: item.name)
            LabeledContent("餐次", value: item.meal.titleZh)
            LabeledContent("日期", value: item.dateKey)
            LabeledContent("热量", value: "\(format(item.calories)) kcal")
            LabeledContent("蛋白质", value: "\(format(item.protein)) g")
            LabeledContent("碳水", value: "\(format(item.carbs)) g")
            LabeledContent("脂肪", value: "\(format(item.fat)) g")
            LabeledContent("膳食纤维", value: "\(format(item.fiber)) g")
            if !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("备注")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.note)
                        .font(.body)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func format(_ value: Double) -> String {
        if !value.isFinite { return "0" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
