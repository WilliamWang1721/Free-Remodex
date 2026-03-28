import SwiftUI
import UIKit

// MARK: - Preference

enum GlassPreference {
    static let storageKey = "codex.useLiquidGlass"

    static var isSupported: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }
}

// MARK: - Glass effect modifier

private struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    @AppStorage(GlassPreference.storageKey) private var glassEnabled = true
    @Environment(\.colorScheme) private var colorScheme
    let regularStyle: Bool
    let shape: S

    func body(content: Content) -> some View {
        let brightFill = Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
            .opacity(regularStyle ? 0.9 : 0.82)
        let borderColor = Color.white.opacity(colorScheme == .dark ? 0.08 : 0.42)

        let softenedContent = content
            .background(brightFill, in: shape)
            .overlay {
                shape
                    .stroke(borderColor, lineWidth: 0.75)
            }

        if #available(iOS 26, *), glassEnabled {
            if regularStyle {
                softenedContent.glassEffect(.regular, in: shape)
            } else {
                softenedContent.glassEffect(in: shape)
            }
        } else {
            softenedContent.background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: - Navigation bar modifier

private struct AdaptiveNavigationBarModifier: ViewModifier {
    @AppStorage(GlassPreference.storageKey) private var glassEnabled = true

    func body(content: Content) -> some View {
        if #available(iOS 26, *), glassEnabled {
            content
        } else {
            content
        }
    }
}

// MARK: - Toolbar item fallback (glass OFF or iOS < 26)

private struct AdaptiveToolbarItemModifier<S: Shape>: ViewModifier {
    @AppStorage(GlassPreference.storageKey) private var glassEnabled = true
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *), glassEnabled {
            content
        } else {
            content
        }
    }
}

// MARK: - View extensions

enum AdaptiveGlassStyle {
    case regular
}

extension View {
    func adaptiveGlass(_ style: AdaptiveGlassStyle, in shape: some Shape) -> some View {
        modifier(AdaptiveGlassModifier(regularStyle: true, shape: shape))
    }

    func adaptiveGlass(in shape: some Shape) -> some View {
        modifier(AdaptiveGlassModifier(regularStyle: false, shape: shape))
    }

    func adaptiveNavigationBar() -> some View {
        modifier(AdaptiveNavigationBarModifier())
    }

    func adaptiveToolbarItem(in shape: some Shape) -> some View {
        modifier(AdaptiveToolbarItemModifier(shape: shape))
    }
}
