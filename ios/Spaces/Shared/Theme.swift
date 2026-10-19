import SwiftUI

/// Warm dark humanist design system inspired by organic obsidian & terracotta surfaces.
enum Theme {
    // MARK: Surfaces
    /// Deep natural charcoal / earthy obsidian (#1A1816)
    static let background = Color(red: 0.102, green: 0.094, blue: 0.086)
    /// Elevated card surface (#221F1B)
    static let card = Color(red: 0.133, green: 0.122, blue: 0.106)
    /// Secondary inner card / pill surface (#2A2621)
    static let cardElevated = Color(red: 0.165, green: 0.149, blue: 0.129)
    /// Floating dock surface (#1E1C19)
    static let dock = Color(red: 0.118, green: 0.110, blue: 0.098)
    /// Segmented control track (#25221E)
    static let segmentTrack = Color(red: 0.145, green: 0.133, blue: 0.118)
    /// Active segment pill (#6A6159)
    static let segmentActive = Color(red: 0.416, green: 0.380, blue: 0.349)

    // MARK: Borders & Dividers
    /// Fine sand border (#3E3730)
    static let border = Color(red: 0.243, green: 0.216, blue: 0.188)
    /// Subtle hairline divider (#2F2A24)
    static let divider = Color(red: 0.184, green: 0.165, blue: 0.141)

    // MARK: Text
    /// Warm off-white cream (#F2EFE9)
    static let textPrimary = Color(red: 0.949, green: 0.937, blue: 0.914)
    /// Muted warm sand (#B7AFA4)
    static let textSecondary = Color(red: 0.718, green: 0.686, blue: 0.643)
    /// Faded earthy sand for captions & metadata (#8E8479)
    static let textTertiary = Color(red: 0.557, green: 0.518, blue: 0.475)
    /// Dark ink used on bright apricot/ochre pills (#1D1814)
    static let inkDark = Color(red: 0.114, green: 0.094, blue: 0.078)

    // MARK: Accents
    /// Glowing warm apricot (#E2A878)
    static let apricot = Color(red: 0.886, green: 0.659, blue: 0.471)
    /// Soft sand-apricot for the floating '+' button (#E0B286)
    static let apricotSoft = Color(red: 0.878, green: 0.698, blue: 0.525)
    /// Terracotta clay for cart icon, progress bar & primary tags (#C97848)
    static let terracotta = Color(red: 0.788, green: 0.471, blue: 0.282)
    /// Deeper burnt sienna for tag pills (#B86B43)
    static let sienna = Color(red: 0.722, green: 0.420, blue: 0.263)
    /// Warm ochre / amber for first tag pill & badges (#C89456)
    static let ochre = Color(red: 0.784, green: 0.580, blue: 0.337)
    /// Earthy taupe for Wish List star & completed checkboxes (#9A7F67)
    static let taupe = Color(red: 0.604, green: 0.498, blue: 0.404)
    /// Warm amber badge fill (#36291D)
    static let amberBadgeFill = Color(red: 0.212, green: 0.161, blue: 0.114)
    /// Warm amber badge text (#E0A96D)
    static let amberBadgeText = Color(red: 0.878, green: 0.663, blue: 0.427)
    /// Neutral pill fill (#322E2A)
    static let neutralPillFill = Color(red: 0.196, green: 0.180, blue: 0.165)

    // MARK: Typography
    /// Editorial humanist serif heading (Georgia Bold, matching the Spaces / New / Notes headers).
    static func serifTitle(_ size: CGFloat = 40) -> Font {
        Font.custom("Georgia-Bold", size: size)
    }

    static func serifSemibold(_ size: CGFloat = 22) -> Font {
        Font.custom("Georgia", size: size).weight(.semibold)
    }

    // MARK: Gradients
    static let activeDockGradient = LinearGradient(
        colors: [
            Color(red: 0.910, green: 0.682, blue: 0.490),
            Color(red: 0.792, green: 0.486, blue: 0.298),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let glowingBorderGradient = LinearGradient(
        colors: [
            Color(red: 0.886, green: 0.659, blue: 0.471).opacity(0.95),
            Color(red: 0.788, green: 0.471, blue: 0.282).opacity(0.65),
            Color(red: 0.450, green: 0.310, blue: 0.220).opacity(0.45),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let progressGradient = LinearGradient(
        colors: [
            Color(red: 0.765, green: 0.447, blue: 0.267),
            Color(red: 0.898, green: 0.612, blue: 0.412),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Organic Checkboxes

/// Circular organic checkbox with a warm terracotta partial ring when open, or taupe fill when checked.
struct OrganicCheckbox: View {
    let checked: Bool
    var accentedRing: Bool = true

    var body: some View {
        ZStack {
            if checked {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.taupe)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkDark)
            } else {
                Circle()
                    .strokeBorder(Theme.border, lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                if accentedRing {
                    Circle()
                        .trim(from: 0.18, to: 0.82)
                        .stroke(
                            Theme.terracotta.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 23, height: 23)
                        .rotationEffect(.degrees(-35))
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: checked)
    }
}

// MARK: - Showcase / Fallback Seed Data

/// Provides the exact items from the design mockups whenever the app is viewed before
/// live backend data has been populated, so the UI is immediately rich and interactive.
enum ShowcaseData {
    static let now = Date()

    static let lists: [ListSummary] = [
        ListSummary(
            id: "showcase-costco",
            name: "‘Costco’ List",
            slug: "costco",
            kind: "shopping",
            itemCount: 2,
            openCount: 2,
            createdAt: now
        ),
        ListSummary(
            id: "showcase-wishlist",
            name: "Wish List",
            slug: "wish-list",
            kind: "wishlist",
            itemCount: 3,
            openCount: 3,
            createdAt: now
        ),
    ]

    static let costcoItems: [ListItem] = [
        ListItem(
            id: "showcase-item-1",
            listId: "showcase-costco",
            text: "Eggs",
            quantity: "1",
            done: false,
            createdAt: now
        ),
        ListItem(
            id: "showcase-item-2",
            listId: "showcase-costco",
            text: "Paper towels",
            quantity: "2",
            done: false,
            createdAt: now
        ),
    ]

    static let wishListItems: [ListItem] = [
        ListItem(
            id: "showcase-wish-1",
            listId: "showcase-wishlist",
            text: "AirPods Max",
            quantity: "1",
            done: false,
            createdAt: now
        ),
        ListItem(
            id: "showcase-wish-2",
            listId: "showcase-wishlist",
            text: "Kindle Scribe",
            quantity: "1",
            done: false,
            createdAt: now
        ),
        ListItem(
            id: "showcase-wish-3",
            listId: "showcase-wishlist",
            text: "Espresso grinder",
            quantity: "1",
            done: false,
            createdAt: now
        ),
    ]

    static func todos(for dateString: String) -> [Todo] {
        [
            Todo(
                id: "showcase-todo-1",
                text: "Call dentist",
                dueDate: dateString,
                done: true,
                doneAt: now,
                createdAt: now
            ),
            Todo(
                id: "showcase-todo-2",
                text: "Renew registration",
                dueDate: dateString,
                done: false,
                doneAt: nil,
                createdAt: now
            ),
        ]
    }

    static let notes: [Note] = [
        Note(
            id: "showcase-note-1",
            text: "What if the garage had a pegboard wall for bikes...",
            title: "Garage bike storage",
            tags: ["garage", "idea"],
            createdAt: now.addingTimeInterval(-2 * 3600),
            updatedAt: now.addingTimeInterval(-2 * 3600)
        ),
        Note(
            id: "showcase-note-2",
            text: "An app that tracks plant watering by photo...",
            title: "App idea: plant watering",
            tags: ["idea", "app"],
            createdAt: now.addingTimeInterval(-26 * 3600),
            updatedAt: now.addingTimeInterval(-26 * 3600)
        ),
        Note(
            id: "showcase-note-3",
            text: "AirPods Max and other electronics...",
            title: "Shopping wish list",
            tags: ["wishlist"],
            createdAt: ISOTimestamp.parse("2026-10-08T18:00:00Z") ?? now.addingTimeInterval(-72 * 3600),
            updatedAt: ISOTimestamp.parse("2026-10-08T18:00:00Z") ?? now.addingTimeInterval(-72 * 3600)
        ),
    ]

    static let captureResponse = CaptureResponse(
        captureId: "showcase-capture-1",
        summary: "✓ Note saved",
        actions: [
            ExecutedAction(
                type: .note,
                summary: "Note saved",
                confidence: 0.95,
                noteId: "showcase-note-1",
                items: ["garage", "idea"]
            )
        ],
        suggestions: [
            Suggestion(
                label: "Did you mean add bike to Costco?",
                listName: "Costco",
                items: ["bike"]
            )
        ]
    )
}
