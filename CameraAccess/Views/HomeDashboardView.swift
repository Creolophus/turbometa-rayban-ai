import SwiftUI

/// Home-only colors: other feature screens keep their existing visual identity.
enum HomeStyle {
    static let coral = Color(red: 0.94, green: 0.30, blue: 0.29)
    static let violet = Color(red: 0.55, green: 0.40, blue: 0.92)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.085, blue: 0.095, alpha: 1)
            : UIColor(red: 0.99, green: 0.99, blue: 0.995, alpha: 1)
    })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

enum HomeFeature: String, Identifiable, CaseIterable {
    case liveAI, quickVision, translate, audioNote, openClaw, liveStream, rtmp, leanEat
    var id: String { rawValue }
}

/// Pure presentation, shared by the live homepage, previews and visual verification.
struct HomeDashboardView: View {
    let device: GlassesDeviceStatus
    let openClawConnected: Bool
    let onOpenSettings: () -> Void
    let onFeature: (HomeFeature) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    @State private var modelPose = WayfarerPose()
    @State private var modelReady = false
    @State private var showingModel = false
    @State private var heroVisible = true
    @State private var scrolling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                deviceRow
                hero
                assistants
                exploration
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in scrolling = phase == .interacting || phase == .decelerating || phase == .animating }
        .background(HomeStyle.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("home.title".localized)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Button(action: onOpenSettings) {
                Image(systemName: "person.fill")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .modifier(HomeGlassControl(shape: Circle(), opaqueColor: HomeStyle.card))
            .accessibilityLabel("home.settings.open".localized)
            .accessibilityIdentifier("home.settings")
        }
        .foregroundStyle(.primary)
    }

    private var deviceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 21))
                .accessibilityHidden(true)
            Text(device.displayName)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Circle().fill(connectionColor).frame(width: 7, height: 7)
                Text(device.statusText).font(.caption)
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.primary.opacity(colorScheme == .dark ? 0.04 : 0.015), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.displayName)
        .accessibilityValue(device.statusText)
        .accessibilityIdentifier("home.device")
    }

    private var connectionColor: Color {
        switch device.linkState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        }
    }

    private var hero: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            if !dynamicTypeSize.isAccessibilitySize {
                heroCopy.padding(.leading, 18).padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            WayfarerSurface(pose: $modelPose, ready: $modelReady, drawsBackground: false, scrolling: scrolling, active: heroVisible && !showingModel) { showingModel = true }
                .frame(maxWidth: .infinity).frame(height: 210)
                .overlay(alignment: .bottomTrailing) {
                    Button { showingModel = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .modifier(HomeGlassControl(shape: Circle(), opaqueColor: .white))
                    .accessibilityLabel("glasses.expand".localized)
                    .padding(10)
                }
            if dynamicTypeSize.isAccessibilitySize { heroCopy.padding(20) }
        }
        .background {
            Image(modelReady ? "HomeGlassesBackdrop" : "HomeGlassesHero").resizable().scaledToFill()
        }
        .foregroundStyle(Color.black.opacity(0.88))
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onScrollVisibilityChange(threshold: 0.01) { heroVisible = $0 }
        .fullScreenCover(isPresented: $showingModel) { WayfarerViewer(pose: modelPose).environment(\.colorScheme, colorScheme) }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("home.hero.eyebrow".localized)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text("Live AI")
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("home.hero.subtitle".localized)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onFeature(.liveAI)
            } label: {
                Label("home.hero.start".localized, systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .modifier(HomeGlassControl(shape: Capsule(), opaqueColor: Color(red: 1, green: 0.87, blue: 0.83)))
            .padding(.top, 6)
            .accessibilityIdentifier("home.liveAI")
        }
    }

    private var assistants: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("home.assistants")
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                assistant(.quickVision, title: "home.assistant.vision", icon: "eye", color: HomeStyle.coral)
                assistant(.translate, title: "home.translate.title", icon: "character.bubble", color: HomeStyle.violet)
                assistant(.audioNote, title: "home.assistant.notes", icon: "waveform", color: .orange)
            }
        }
    }

    private func assistant(_ feature: HomeFeature, title: String, icon: String, color: Color) -> some View {
        Button {
            onFeature(feature)
        } label: {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(color)
                    .frame(height: 30)
                    .accessibilityHidden(true)
                Text(title.localized)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(.vertical, 6)
            .background(color.opacity(colorScheme == .dark ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.\(feature.rawValue)")
    }

    private var exploration: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("home.explore")
            VStack(spacing: 0) {
                exploreRow(.openClaw, title: "OpenClaw", subtitle: openClawConnected ? "home.openclaw.connected" : "home.explore.openclaw", icon: "cube", color: HomeStyle.coral)
                rowDivider
                exploreRow(.liveStream, title: "home.livestream.title".localized, subtitle: "home.explore.live", icon: "dot.radiowaves.left.and.right", color: HomeStyle.coral)
                rowDivider
                exploreRow(.rtmp, title: "home.rtmp.title".localized, subtitle: nil, icon: "icloud.and.arrow.up", color: HomeStyle.violet, badge: "home.experimental".localized)
                rowDivider
                exploreRow(.leanEat, title: "LeanEat", subtitle: "home.explore.food", icon: "leaf", color: .green)
            }
            .background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(.primary.opacity(0.02)).padding(.leading, 52)
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(key.localized).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private func exploreRow(_ feature: HomeFeature, title: String, subtitle: String?, icon: String, color: Color, badge: String? = nil) -> some View {
        Button {
            onFeature(feature)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(color)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(HomeStyle.violet)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(HomeStyle.violet.opacity(0.1), in: Capsule())
                        }
                    }
                    if let subtitle {
                        Text(subtitle.localized).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.\(feature.rawValue)")
    }
}

private struct HomeGlassControl<S: Shape>: ViewModifier {
    let shape: S
    let opaqueColor: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(opaqueColor, in: shape)
                .overlay(shape.stroke(.primary.opacity(0.12), lineWidth: 0.5))
        } else {
            content.glassEffect(.regular.interactive(), in: shape)
        }
    }
}

#Preview("Home — Light") {
    HomeDashboardView(device: GlassesDeviceStatus(identifier: "preview", name: "我的 Ray-Ban", linkState: .connected), openClawConnected: false, onOpenSettings: {}, onFeature: { _ in })
        .preferredColorScheme(.light)
}

#Preview("Home — Dark") {
    HomeDashboardView(device: .disconnected, openClawConnected: true, onOpenSettings: {}, onFeature: { _ in })
        .preferredColorScheme(.dark)
}
