import SwiftUI

public struct AvatarSelfieIntroView: View {
    private let onBack: () -> Void
    private let onCreateAvatar: (() -> Void)?
    private let onLearnMore: (() -> Void)?

    public init(
        onBack: @escaping () -> Void = {},
        onCreateAvatar: (() -> Void)? = nil,
        onLearnMore: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        self.onCreateAvatar = onCreateAvatar
        self.onLearnMore = onLearnMore
    }

    public var body: some View {
        let theme = AvatarTheme.current

        ZStack {
            theme.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0.0) {
                self.navigationBar(theme: theme)
                    .padding(.top, 18.0)

                AvatarPeopleCard()
                    .padding(.top, 28.0)

                Text("Avatars")
                    .font(AvatarTypography.bodyTitle)
                    .foregroundColor(theme.primaryText)
                    .padding(.top, 12.0)

                Text("Say more with Avatars on Sends Messenger")
                    .font(AvatarTypography.body)
                    .foregroundColor(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 6.0)

                AvatarIntroActionRow(
                    title: "Create your avatar",
                    style: .accent,
                    theme: theme,
                    action: { self.onCreateAvatar?() }
                )
                .padding(.top, 22.0)

                AvatarIntroActionRow(
                    title: "Learn more",
                    style: .navigation,
                    theme: theme,
                    action: { self.onLearnMore?() }
                )
                .padding(.top, 16.0)

                Spacer(minLength: 0.0)
            }
            .padding(.horizontal, AvatarMetrics.horizontalInset)
        }
    }

    private func navigationBar(theme: AvatarTheme) -> some View {
        ZStack {
            Text("Avatar")
                .font(AvatarTypography.screenTitle)
                .foregroundColor(theme.primaryText)
                .frame(maxWidth: .infinity)

            HStack {
                Button(action: self.onBack) {
                    HStack(spacing: 6.0) {
                        Text("‹")
                            .font(AvatarTypography.backChevron)
                            .frame(width: 9.0)
                        Text("Back")
                            .font(AvatarTypography.navigationButton)
                    }
                    .foregroundColor(theme.primaryText)
                    .padding(.horizontal, 12.0)
                    .frame(height: AvatarMetrics.navButtonHeight)
                    .background(theme.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(theme.navigationButtonBorder, lineWidth: 1.0)
                    )
                }
                .buttonStyle(.plain)
                .accessibility(label: Text("Back"))

                Spacer()
            }
        }
        .frame(height: AvatarMetrics.navButtonHeight)
    }
}

private struct AvatarIntroActionRow: View {
    enum Style {
        case accent
        case navigation
    }

    let title: String
    let style: Style
    let theme: AvatarTheme
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack {
                Text(self.title)
                    .font(AvatarTypography.action)
                    .foregroundColor(self.style == .accent ? self.theme.accent : self.theme.primaryText)
                Spacer()
                if self.style == .navigation {
                    Text("›")
                        .font(AvatarTypography.disclosureChevron)
                        .foregroundColor(self.theme.secondaryText)
                }
            }
            .padding(.horizontal, 14.0)
            .frame(height: AvatarMetrics.actionRowHeight)
            .background(self.theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AvatarMetrics.rowCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AvatarMetrics.rowCornerRadius, style: .continuous)
                    .stroke(self.theme.separator, lineWidth: 1.0)
                    .opacity(self.style == .accent ? 0.65 : 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibility(label: Text(self.title))
    }
}

private struct AvatarPeopleCard: View {
    var body: some View {
        Image("AvatarIntro", bundle: AvatarResourceBundle.bundle)
            .resizable()
            .scaledToFit()
        .aspectRatio(1.08, contentMode: .fit)
        .accessibility(hidden: true)
    }
}
