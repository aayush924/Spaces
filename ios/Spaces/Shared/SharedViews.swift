import SwiftUI

// MARK: - Action presentation

extension ActionType {
    var symbolName: String {
        switch self {
        case .note: return "note.text"
        case .listAdd: return "cart.badge.plus"
        case .todoAdd: return "checklist"
        case .todoComplete: return "checkmark.circle.fill"
        case .listItemRemove: return "cart.badge.minus"
        case .unknown: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .note: return Theme.ochre
        case .listAdd: return Theme.terracotta
        case .todoAdd: return Theme.apricot
        case .todoComplete: return Theme.taupe
        case .listItemRemove: return Theme.sienna
        case .unknown: return Theme.apricotSoft
        }
    }
}

extension ExecutedAction {
    var title: String {
        switch type {
        case .note:
            return "Note saved"
        case .listAdd:
            let count = items.count
            return "\(count) item\(count == 1 ? "" : "s") → \(listName ?? "list")"
        case .todoAdd:
            let count = items.count
            let day = dueDate.map { LocalDate.display($0) } ?? "someday"
            return "\(count) todo\(count == 1 ? "" : "s") for \(day)"
        case .todoComplete:
            let count = items.count
            return "Completed \(count) todo\(count == 1 ? "" : "s")"
        case .listItemRemove:
            let count = items.count
            return "Removed \(count) from \(listName ?? "list")"
        case .unknown(let raw):
            return raw
        }
    }

    var isLowConfidence: Bool { (confidence ?? 1) < 0.6 }
}

// MARK: - Reusable views

/// Warm ochre & terracotta tag pills matching the Notes and New screen mockups.
struct TagChips: View {
    let tags: [String]
    var style: Style = .warmSolid

    enum Style {
        case warmSolid
        case subtlePill
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    let cleanTag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
                    switch style {
                    case .warmSolid:
                        let isFirst = (index % 2 == 0) && tags.count > 1 && cleanTag != "wishlist"
                        Text("#\(cleanTag)")
                            .font(.system(size: 13.5, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4)
                            .background(
                                isFirst ? Theme.ochre : Theme.sienna,
                                in: Capsule()
                            )
                            .foregroundStyle(isFirst ? Theme.inkDark : Theme.textPrimary)
                    case .subtlePill:
                        Text("#\(cleanTag)")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.neutralPillFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.ochre)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.apricot)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.ochre.opacity(0.45), lineWidth: 1)
        )
    }
}

struct SetupPrompt: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.apricot)
            Text("Preview mode active. Add your server URL & API token in **Settings** for live sync.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

/// Presents an alert whenever the bound message becomes non-nil.
struct ErrorAlertModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(message ?? "") }
        )
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlertModifier(message: message))
    }
}

/// Converts any error into a user-facing message, or nil for cancellations.
func userMessage(for error: Error) -> String? {
    if error is CancellationError { return nil }
    if let urlError = error as? URLError, urlError.code == .cancelled { return nil }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}
