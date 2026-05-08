import SwiftUI

public struct AvatarCreationIntroView: View {
    @State private var selectedIndex: Int = 0

    private let onBack: () -> Void
    private let onCreateFromSelfie: (() -> Void)?
    private let onChooseAnimalAvatar: (() -> Void)?
    private let onCreateManually: (() -> Void)?
    private let onTermsOfService: (() -> Void)?

    private let slides: [AvatarCreationSlide] = [
        AvatarCreationSlide(
            title: "Make your own avatar",
            subtitle: "Snap a selfie to create a starting point, then customize and style your avatar however you like.",
            assetName: "AvatarCreationSelfie"
        ),
        AvatarCreationSlide(
            title: "Express yourself",
            subtitle: "Interact with others as your new avatar, with more expressive, authentic stickers, profile pics and more!",
            assetName: "AvatarCreationExpress"
        ),
        AvatarCreationSlide(
            title: "Evolve your style",
            subtitle: "Style yourself for any occasion with a choice of outfits, hair colors and accessories.",
            assetName: "AvatarCreationStyle"
        )
    ]

    public init(
        onBack: @escaping () -> Void = {},
        onCreateFromSelfie: (() -> Void)? = nil,
        onChooseAnimalAvatar: (() -> Void)? = nil,
        onCreateManually: (() -> Void)? = nil,
        onTermsOfService: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        self.onCreateFromSelfie = onCreateFromSelfie
        self.onChooseAnimalAvatar = onChooseAnimalAvatar
        self.onCreateManually = onCreateManually
        self.onTermsOfService = onTermsOfService
    }

    public var body: some View {
        let theme = AvatarTheme.current

        GeometryReader { proxy in
            let bottomHeight = min(max(proxy.size.height * 0.39, 280.0), 330.0)
            let imageHeight = max(0.0, proxy.size.height - bottomHeight)

            ZStack {
                theme.background.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0.0) {
                    AvatarCreationHero(
                        slide: self.slides[self.selectedIndex],
                        theme: theme,
                        height: imageHeight,
                        onBack: self.onBack
                    )
                    .gesture(self.pageGesture)

                    AvatarCreationBottomPanel(
                        slides: self.slides,
                        selectedIndex: self.selectedIndex,
                        theme: theme,
                        onSelectSlide: { index in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.selectedIndex = index
                            }
                        },
                        onCreateFromSelfie: { self.onCreateFromSelfie?() },
                        onChooseAnimalAvatar: { self.onChooseAnimalAvatar?() },
                        onCreateManually: { self.onCreateManually?() },
                        onTermsOfService: { self.onTermsOfService?() }
                    )
                    .frame(height: bottomHeight)
                    .gesture(self.pageGesture)
                }
            }
        }
    }

    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 24.0)
            .onEnded { value in
                if value.translation.width < -44.0 {
                    self.moveToSlide(self.selectedIndex + 1)
                } else if value.translation.width > 44.0 {
                    self.moveToSlide(self.selectedIndex - 1)
                }
            }
    }

    private func moveToSlide(_ index: Int) {
        let nextIndex = min(max(index, 0), self.slides.count - 1)
        guard nextIndex != self.selectedIndex else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            self.selectedIndex = nextIndex
        }
    }
}

private struct AvatarCreationSlide {
    let title: String
    let subtitle: String
    let assetName: String
}

private struct AvatarCreationHero: View {
    let slide: AvatarCreationSlide
    let theme: AvatarTheme
    let height: CGFloat
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(self.slide.assetName, bundle: AvatarResourceBundle.bundle)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: self.height)
                .clipped()
                .accessibility(hidden: true)

            Button(action: self.onBack) {
                HStack(spacing: 5.0) {
                    Text("‹")
                        .font(AvatarTypography.backChevron)
                        .frame(width: 9.0)
                    Text("Back")
                        .font(AvatarTypography.navigationButton)
                }
                .foregroundColor(self.theme.primaryText)
                .padding(.horizontal, 11.0)
                .frame(height: AvatarMetrics.navButtonHeight)
                .background(self.theme.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(self.theme.separator, lineWidth: 1.0)
                        .opacity(0.7)
                )
            }
            .buttonStyle(.plain)
            .accessibility(label: Text("Back"))
            .padding(.top, 18.0)
            .padding(.leading, 15.0)
        }
        .frame(height: self.height)
        .clipped()
    }
}

private struct AvatarCreationBottomPanel: View {
    let slides: [AvatarCreationSlide]
    let selectedIndex: Int
    let theme: AvatarTheme
    let onSelectSlide: (Int) -> Void
    let onCreateFromSelfie: () -> Void
    let onChooseAnimalAvatar: () -> Void
    let onCreateManually: () -> Void
    let onTermsOfService: () -> Void

    var body: some View {
        VStack(spacing: 0.0) {
            Rectangle()
                .fill(self.theme.separator)
                .opacity(0.35)
                .frame(height: 1.0)

            AvatarPageDots(
                count: self.slides.count,
                selectedIndex: self.selectedIndex,
                theme: self.theme,
                onSelect: self.onSelectSlide
            )
            .padding(.top, 26.0)

            Text(self.slides[self.selectedIndex].title)
                .font(AvatarTypography.bodyTitle)
                .foregroundColor(self.theme.primaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 17.0)

            Text(self.slides[self.selectedIndex].subtitle)
                .font(AvatarTypography.body)
                .foregroundColor(self.theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36.0)
                .padding(.top, 7.0)

            Button(action: self.onCreateFromSelfie) {
                Text("Create from selfie")
                    .font(AvatarTypography.primaryAction)
                    .foregroundColor(self.theme.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48.0)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [self.theme.primaryButtonStart, self.theme.primaryButtonEnd]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9.0, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 27.0)
            .padding(.top, 20.0)

            Button(action: self.onChooseAnimalAvatar) {
                Text("Choose an animal avatar")
                    .font(AvatarTypography.primaryAction)
                    .foregroundColor(self.theme.accent)
                    .frame(height: 43.0)
            }
            .buttonStyle(.plain)

            Button(action: self.onCreateManually) {
                Text("Create manually")
                    .font(AvatarTypography.primaryAction)
                    .foregroundColor(self.theme.primaryText)
                    .frame(height: 32.0)
            }
            .buttonStyle(.plain)

            Button(action: self.onTermsOfService) {
                (Text("Avatars are subject to our ")
                    .foregroundColor(self.theme.secondaryText)
                 + Text("terms of service.")
                    .foregroundColor(self.theme.accent))
                    .font(AvatarTypography.caption)
            }
            .buttonStyle(.plain)
            .padding(.top, 13.0)

            Spacer(minLength: 0.0)
        }
        .background(self.theme.background)
    }
}

private struct AvatarPageDots: View {
    let count: Int
    let selectedIndex: Int
    let theme: AvatarTheme
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 5.0) {
            ForEach(0..<self.count, id: \.self) { index in
                Button(action: { self.onSelect(index) }) {
                    Capsule()
                        .fill(index == self.selectedIndex ? self.theme.accent : self.theme.accent.opacity(0.35))
                        .frame(width: index == self.selectedIndex ? 13.0 : 7.0, height: 7.0)
                }
                .buttonStyle(.plain)
                .accessibility(label: Text("Slide \(index + 1)"))
            }
        }
    }
}
