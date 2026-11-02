import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Home: start a project from today's footage, or pick up a recent one.
struct HomeView: View {
    @Bindable private var onboarding = OnboardingStore.shared
    @Bindable private var changelog = ChangelogStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader()
            if ProjectRegistry.shared.entries.isEmpty {
                FirstLaunchView()
            } else {
                HStack(alignment: .top, spacing: AppTheme.Home.columnGap) {
                    StartFromFootage()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    MyProjectsSection()
                        .frame(minWidth: AppTheme.Home.projectsMinWidth, idealWidth: AppTheme.Home.projectsWidth, maxWidth: AppTheme.Home.projectsWidth)
                }
                .padding(.horizontal, AppTheme.Home.contentPadding)
                .padding(.top, AppTheme.Spacing.xlXxl)
                .padding(.bottom, AppTheme.Home.columnGap)
            }
        }
        .frame(
            minWidth: AppTheme.Window.homeMin.width,
            maxWidth: .infinity,
            minHeight: AppTheme.Window.homeMin.height,
            maxHeight: .infinity
        )
        .background(AppTheme.Background.baseColor)
        .foregroundStyle(AppTheme.Text.primaryColor)
        .focusEffectDisabled()
        .task { await VisualModelLoader.shared.prepare() }
        .onAppear { changelog.checkForWhatsNew() }
        .overlay {
            ZStack {
                if !onboarding.isComplete {
                    OnboardingOverlay(onboarding: onboarding)
                } else if let entry = changelog.pending {
                    UpdateOverlay(entry: entry, changelogURL: changelog.changelogURL) {
                        changelog.dismiss()
                    }
                }
            }
            .allowsHitTesting(isModalOverlayPresented)
        }
        .animation(.easeInOut(duration: AppTheme.Anim.transition), value: isModalOverlayPresented)
    }

    private var isModalOverlayPresented: Bool {
        !onboarding.isComplete || changelog.pending != nil
    }
}

private struct HomeHeader: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VeeCutWordmark(markSize: AppTheme.IconSize.lgXl, fontSize: AppTheme.FontSize.title1)
            Spacer(minLength: 0)
            Button {
                AppState.shared.openProjectFromPanel()
            } label: {
                Label(L10n.string("Open Project…"), systemImage: "folder")
            }
            .controlSize(.regular)
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .help(L10n.string("Settings"))
            .accessibilityLabel(L10n.string("Settings"))
        }
        .padding(.leading, AppTheme.Home.trafficLightInset)
        .padding(.trailing, AppTheme.Spacing.xl)
        .frame(height: AppTheme.Home.headerHeight)
    }
}

/// The coach's question and the place to drop today's footage.
private struct StartFromFootage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text(L10n.string("What are we making today?"))
                .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.Home.questionSize).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("Drop the clips you shot. Vee watches them, suggests a few videos you could make, and cuts a first edit to your song. You keep what you like."))
                .font(.system(size: AppTheme.FontSize.lg))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .frame(maxWidth: AppTheme.Home.subtitleWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            FootageDropZone()
        }
    }
}

private struct FootageDropZone: View {
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            VeeIllustration(name: .footageBox, height: AppTheme.Home.footageIllustrationHeight)
            VStack(spacing: AppTheme.Spacing.xs) {
                Text(L10n.string("Drop today's footage here"))
                    .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.xl).weight(.semibold))
                Text(L10n.string("Videos, photos or a whole folder from your camera"))
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }
            StartButtons()
        }
        .padding(AppTheme.Spacing.xlXxl)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Home.dropMinHeight, maxHeight: .infinity)
        .background(AppTheme.Tint.lilacColor.opacity(isTargeted ? AppTheme.Opacity.prominent : AppTheme.Opacity.medium),
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .strokeBorder(AppTheme.Accent.primary.opacity(isTargeted ? AppTheme.Opacity.opaque : AppTheme.Opacity.medium),
                              style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thick, dash: [AppTheme.Spacing.sm, AppTheme.Spacing.xs]))
        )
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: FootageDrop.accept)
    }
}

private struct StartButtons: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button(L10n.string("Choose Footage…")) { FootageDrop.choose() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button(L10n.string("Empty Project")) { AppState.shared.createProjectInteractively() }
                .controlSize(.large)
        }
    }
}

/// No projects yet: just the question and a way in; footage can be dropped anywhere.
private struct FirstLaunchView: View {
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xlXxl) {
            VeeIllustration(name: .footageBox, height: AppTheme.Home.firstLaunchIllustrationHeight)
            Text(L10n.string("What are we making today?"))
                .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.Home.firstLaunchQuestionSize).weight(.semibold))
                .multilineTextAlignment(.center)
            Text(L10n.string("Drop the clips you shot anywhere in this window. Vee watches them, suggests a few videos you could make, and cuts a first edit to your song. You keep what you like."))
                .font(.system(size: AppTheme.FontSize.lg))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: AppTheme.Home.subtitleWidth)
            StartButtons()
        }
        .padding(AppTheme.Home.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Tint.lilacColor.opacity(isTargeted ? AppTheme.Opacity.medium : 0))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: FootageDrop.accept)
    }
}

/// Footage into a new project, from a drop or the open panel.
@MainActor
enum FootageDrop {
    static func accept(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !fileProviders.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await fileURL(from: provider) { urls.append(url) }
            }
            AppState.shared.createProject(fromFootage: urls)
        }
        return true
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    static func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.movie, .image, .audio, .folder]
        panel.prompt = L10n.string("Start Project")
        panel.begin { response in
            guard response == .OK else { return }
            AppState.shared.createProject(fromFootage: panel.urls)
        }
    }
}

// MARK: - Home window controller

@MainActor
final class HomeWindowController: NSWindowController {
    static let shared = HomeWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: HomeView().appLocalization().tint(AppTheme.Accent.primary))
        hostingController.sizingOptions = .minSize
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(AppTheme.Window.homeDefault)
        window.minSize = AppTheme.Window.homeMin
        window.title = AppIdentity.name
        window.backgroundColor = AppTheme.Background.base
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior = [.fullScreenNone]
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
