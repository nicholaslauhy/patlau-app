import SwiftUI

enum Theme {
    static let blue = Color(red: 22/255, green: 119/255, blue: 200/255)
    static let blueDark = Color(red: 15/255, green: 98/255, blue: 167/255)
    static let teal = Color(red: 15/255, green: 118/255, blue: 110/255)
    static let green = Color(red: 22/255, green: 135/255, blue: 101/255)
    static let amber = Color(red: 217/255, green: 154/255, blue: 25/255)
    static let red = Color(red: 220/255, green: 76/255, blue: 90/255)
    static let purple = Color(red: 121/255, green: 80/255, blue: 179/255)
    static let ink = Color(red: 23/255, green: 32/255, blue: 51/255)
    static let secondaryText = Color(red: 100/255, green: 116/255, blue: 139/255)
    static let background = Color(red: 246/255, green: 248/255, blue: 251/255)
    static let raisedBackground = Color.white
    static let border = Color(red: 224/255, green: 231/255, blue: 239/255)

    static func colour(for programme: Programme) -> Color {
        switch programme {
        case .weekend: blue
        case .weekday: Color.indigo
        case .matchplay: purple
        case .oneToOne: green
        }
    }

    static func colour(for group: OperationGroup) -> Color {
        switch group {
        case .weekend: blue
        case .weekday: Color.indigo
        case .matchplay: purple
        case .oneToOne: green
        case .makeup: amber
        case .support: teal
        case .account: secondaryText
        }
    }

    static func colour(for role: UserRole) -> Color {
        switch role {
        case .superuser: red
        case .admin: purple
        case .member: blue
        }
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Theme.raisedBackground,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border)
            )
            .shadow(color: Theme.ink.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    func appCard(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }

    func touchTarget() -> some View {
        frame(minHeight: 44)
    }

    /// Keeps the end of database-backed directories above the floating iOS 26
    /// tab bar. Earlier iOS versions use a non-overlaying tab bar and already
    /// provide the correct safe-area inset themselves.
    @ViewBuilder
    func appTabBarClearance() -> some View {
        if #available(iOS 26.0, *) {
            safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: 86)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            self
        }
    }
}

struct AppMark: View {
    let size: CGFloat

    var body: some View {
        Image("PatLauIcon")
            .resizable()
            .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Theme.blue.opacity(0.16), radius: 9, y: 4)
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let text: String
    var color: Color = Theme.blue

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.blue)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .appCard()
    }
}

struct LoadingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.blue)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("Please wait. This may take a moment.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct NoticeView: View {
    @EnvironmentObject private var state: AppState
    let notice: AppNotice

    private var color: Color {
        switch notice.kind {
        case .success: Theme.green
        case .error: Theme.red
        case .info: Theme.blue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.kind == .success
                  ? "checkmark.circle.fill"
                  : notice.kind == .error
                  ? "exclamationmark.triangle.fill"
                  : "info.circle.fill")
            Text(notice.text)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .foregroundStyle(color)
        .padding(.leading, 13)
        .padding(.trailing, 5)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.28)))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .accessibilityIdentifier("app-notice")
        .task {
            try? await Task.sleep(for: .seconds(notice.kind == .error ? 10 : 6))
            dismiss()
        }
    }

    private func dismiss() {
        guard state.notice?.id == notice.id else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            state.notice = nil
        }
    }
}

private struct AppNoticeHostModifier: ViewModifier {
    @EnvironmentObject private var state: AppState

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let notice = state.notice {
                NoticeView(notice: notice)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
    }
}

extension View {
    /// Displays transient feedback below the active navigation header. The
    /// page content makes room while the notice is visible, keeping it clear
    /// of both controls and the persistent tab bar.
    func appNoticeHost() -> some View {
        modifier(AppNoticeHostModifier())
    }
}

struct SearchHighlight: View {
    let text: String
    let query: String

    var body: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(text)
        } else {
            Text(attributed)
        }
    }

    private var attributed: AttributedString {
        var value = AttributedString(text)
        var searchStart = value.startIndex
        while searchStart < value.endIndex,
              let range = value[searchStart...].range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) {
            value[range].backgroundColor = .yellow.opacity(0.7)
            searchStart = range.upperBound
        }
        return value
    }
}
