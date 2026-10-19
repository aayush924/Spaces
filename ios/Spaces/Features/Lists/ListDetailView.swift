import SwiftUI

struct ListDetailView: View {
    let name: String
    let symbolName: String
    @Environment(AppSettings.self) private var settings
    @State private var model: ListDetailViewModel
    @FocusState private var addFocused: Bool

    init(listID: String, name: String, symbolName: String = "list.bullet") {
        self.name = name
        self.symbolName = symbolName
        _model = State(initialValue: ListDetailViewModel(listID: listID))
    }

    init(list: ListSummary) {
        self.init(listID: list.id, name: list.name, symbolName: list.symbolName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(name)
                    .font(Theme.serifTitle(34))
                    .foregroundStyle(Theme.textPrimary)

                if let error = model.errorMessage {
                    ErrorBanner(message: error) {
                        Task { await model.load(api: settings.api, isConfigured: settings.isConfigured) }
                    }
                }

                // Quick-add input row
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.apricot)
                    TextField("Add item…", text: $model.newItemText)
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.apricot)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            Task {
                                await model.add(api: settings.api, isConfigured: settings.isConfigured)
                                addFocused = true
                            }
                        }
                    if !model.newItemText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add") {
                            Task { await model.add(api: settings.api, isConfigured: settings.isConfigured) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.apricot)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

                if !model.openItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TO GET")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.3)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(model.openItems.enumerated()), id: \.element.id) { index, item in
                                DetailItemRow(
                                    item: item,
                                    onToggle: {
                                        Task { await model.toggle(item, api: settings.api, isConfigured: settings.isConfigured) }
                                    },
                                    onDelete: {
                                        Task { await model.delete(item, api: settings.api, isConfigured: settings.isConfigured) }
                                    }
                                )
                                if index < model.openItems.count - 1 {
                                    Divider().overlay(Theme.divider).padding(.leading, 54)
                                }
                            }
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                    }
                }

                if !model.doneItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("COMPLETED")
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(1.3)
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Button("Clear completed") {
                                Task { await model.clearCompleted(api: settings.api, isConfigured: settings.isConfigured) }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.apricot)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(model.doneItems.enumerated()), id: \.element.id) { index, item in
                                DetailItemRow(
                                    item: item,
                                    onToggle: {
                                        Task { await model.toggle(item, api: settings.api, isConfigured: settings.isConfigured) }
                                    },
                                    onDelete: {
                                        Task { await model.delete(item, api: settings.api, isConfigured: settings.isConfigured) }
                                    }
                                )
                                if index < model.doneItems.count - 1 {
                                    Divider().overlay(Theme.divider).padding(.leading, 54)
                                }
                            }
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load(api: settings.api, isConfigured: settings.isConfigured) }
        .task { await model.load(api: settings.api, isConfigured: settings.isConfigured) }
    }
}

private struct DetailItemRow: View {
    let item: ListItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                HStack(spacing: 14) {
                    OrganicCheckbox(checked: item.done, accentedRing: true)
                    Text(item.text)
                        .font(.system(size: 17))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? Theme.textTertiary : Theme.textPrimary)
                    Spacer()
                    if let quantity = item.quantity, !quantity.isEmpty {
                        Text("Qty: \(quantity)")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
