import SwiftUI

enum KegeTheme {
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.910)
    static let card = Color(red: 1.0, green: 0.988, blue: 0.965)
    static let ink = Color(red: 0.110, green: 0.098, blue: 0.086)
    static let accent = Color(red: 0.702, green: 0.227, blue: 0.227)
    static let sage = Color(red: 0.310, green: 0.435, blue: 0.357)
    static let ochre = Color(red: 0.757, green: 0.522, blue: 0.247)
    static let line = Color.black.opacity(0.06)

    static var titleFont: Font { .system(.title2, design: .serif).weight(.semibold) }
    static var displayFont: Font { .system(.largeTitle, design: .serif).weight(.bold) }
}

struct KegeCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KegeTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(KegeTheme.line, lineWidth: 1)
            )
    }
}

struct ClassRowView: View {
    let session: ClassSession
    var emphasize: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startTimeLabel)
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                Text(session.endTimeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(emphasize ? KegeTheme.accent : KegeTheme.ochre)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(KegeTheme.ink)
                HStack(spacing: 8) {
                    if !session.location.isEmpty {
                        Label(session.location, systemImage: "mappin.and.ellipse")
                    }
                    if !session.teacher.isEmpty {
                        Label(session.teacher, systemImage: "person")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title) \(session.timeRangeLabel) \(session.location)")
    }
}

struct EmptyStateView: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(KegeTheme.accent)
            Text(title)
                .font(KegeTheme.titleFont)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
