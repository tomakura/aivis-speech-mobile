import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AivisUI {
    static let accent = Color(red: 0.255, green: 0.635, blue: 0.925)
    static let editorAccent = Color(red: 0.255, green: 0.635, blue: 0.925)
    static let success = Color(red: 0.13, green: 0.48, blue: 0.29)
    static let warning = Color(red: 0.78, green: 0.41, blue: 0.07)
    static let mutedText = Color.secondary
    static let radius: CGFloat = 8
    static let sectionSpacing: CGFloat = 16

    #if canImport(UIKit)
    static let accentMuted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.435, blue: 0.663, alpha: 0.35)
            : UIColor(red: 0.255, green: 0.635, blue: 0.925, alpha: 0.18)
    })
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.18, blue: 0.20, alpha: 1.0)
            : UIColor(red: 0.71, green: 0.86, blue: 0.97, alpha: 1.0)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.094, green: 0.302, blue: 0.486, alpha: 1.0)
            : UIColor.white
    })
    static let secondarySurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.212, green: 0.227, blue: 0.247, alpha: 1.0)
            : UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
    })
    static let border = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.231, green: 0.243, blue: 0.263, alpha: 1.0)
            : UIColor(red: 0.165, green: 0.18, blue: 0.20, alpha: 0.2)
    })
    #elseif canImport(AppKit)
    static let accentMuted = Color(nsColor: .controlAccentColor).opacity(0.16)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let secondarySurface = Color(nsColor: .underPageBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    #else
    static let accentMuted = accent.opacity(0.16)
    static let background = Color(.systemBackground)
    static let surface = Color(.secondarySystemBackground)
    static let secondarySurface = Color(.tertiarySystemBackground)
    static let border = Color.secondary.opacity(0.25)
    #endif
}

struct AivisScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(AivisUI.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)

                    content
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(AivisUI.background.ignoresSafeArea())
    }
}

struct AivisSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AivisUI.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AivisUI.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AivisUI.surface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                .stroke(AivisUI.border, lineWidth: 1)
        )
    }
}

struct AivisOverview: View {
    let title: String
    let detail: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AivisUI.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowPills(items: items)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AivisUI.secondarySurface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                .stroke(AivisUI.border, lineWidth: 1)
        )
    }
}

struct FlowPills: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.filter { !$0.isEmpty }, id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AivisUI.accentMuted, in: Capsule())
                        .foregroundStyle(AivisUI.accent)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct AivisNotice: View {
    enum Tone {
        case info
        case warning

        var color: Color {
            switch self {
            case .info:
                return AivisUI.accent
            case .warning:
                return AivisUI.warning
            }
        }

        var imageName: String {
            switch self {
            case .info:
                return "info.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    let text: String
    var tone: Tone = .info

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.imageName)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                .stroke(tone.color.opacity(0.25), lineWidth: 1)
        )
    }
}

struct AivisKeyValueRow: View {
    let title: String
    let value: String
    var imageName: String?
    var tint: Color = AivisUI.accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let imageName {
                Image(systemName: imageName)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AivisUI.mutedText)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct AivisDivider: View {
    var body: some View {
        Divider()
            .overlay(AivisUI.border)
    }
}
