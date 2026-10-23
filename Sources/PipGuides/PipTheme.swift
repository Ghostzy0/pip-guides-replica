import SwiftUI
import AppKit

/// Original native adaptation. No private motion library or copied character asset.
enum Edition {
    #if GUIDES_REPLICA
    static let replica = true
    #else
    static let replica = false
    #endif
    #if GUIDES_ENHANCEMENTS || ENHANCED
    static let enhanced = true
    static let version = "0.1.0-alpha.2"
    #else
    static let enhanced = false
    static let version = "0.1.0-alpha.1"
    #endif
    #if BASELINE
    static let baseline = true
    static let name = replica ? "Guides Replica" : (enhanced ? "Guides Enhanced" : "Guides Baseline")
    #else
    static let baseline = false
    static let name = enhanced ? "Pip Guides Enhanced" : "Pip Guides"
    #endif
}

enum GuideTheme: String, CaseIterable {
    case paper, oat, harbour, fern, plum, saffron, slate, graphite, coast
    var title: String { rawValue.capitalized }
    var anchors: (light: [UInt], dark: [UInt]) {
        switch self {
        case .paper: return ([0xFFFFFF,0x121211,0x121211],[0x0F0F0E,0xF1F1EE,0xF1F1EE])
        case .oat: return ([0xF6F2EA,0x1E1B16,0xB4532A],[0x181512,0xF2EDE3,0xE0865C])
        case .harbour: return ([0xF3F6FA,0x14202E,0x1F5FBF],[0x0F1722,0xE6EDF6,0x6FA3F0])
        case .fern: return ([0xF2F6F1,0x16231A,0x2F7A4B],[0x101A13,0xE4EFE6,0x6CC18A])
        case .plum: return ([0xF8F3F6,0x25171F,0x8A2F67],[0x1B1218,0xF4E8EF,0xD77DB3])
        case .saffron: return ([0xFAF6EC,0x231C0E,0xA86A00],[0x1A1509,0xF7EFD9,0xF0B43A])
        case .slate: return ([0xF4F5F7,0x1B1E24,0x4A5568],[0x121418,0xE8EAEE,0x9AA5B8])
        case .graphite: return ([0xFFFFFF,0x0B0B0C,0x111111],[0x0B0B0C,0xF5F5F5,0xFFFFFF])
        case .coast: return ([0xF1F8F8,0x11262A,0x0F7C84],[0x0D1A1C,0xE2F1F2,0x55C2CA])
        }
    }
}

struct PipPalette {
    let canvas: Color, ink: Color, surface: Color, raised: Color, fill: Color, selected: Color
    let line: Color, controlLine: Color, secondary: Color, danger: Color, dangerSoft: Color
    init(theme: GuideTheme = .paper, dark: Bool = false, contrast: Bool = false) {
        if Edition.baseline {
            canvas = Color(nsColor: .windowBackgroundColor); ink = .primary; surface = Color(nsColor: .controlBackgroundColor); raised = canvas
            fill = Color.primary.opacity(0.035); selected = Color.primary.opacity(0.07); line = Color.secondary.opacity(0.3)
            controlLine = line; secondary = .secondary; danger = .red; dangerSoft = Color.red.opacity(0.08)
            return
        }
        func rgb(_ hex: UInt) -> NSColor { NSColor(srgbRed: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, alpha: 1) }
        let a = dark ? theme.anchors.dark : theme.anchors.light, bg = rgb(a[0]), fg = rgb(a[1])
        func mix(_ fraction: CGFloat) -> Color { Color(nsColor: bg.blended(withFraction: fraction, of: fg) ?? bg) }
        canvas = Color(nsColor: bg); ink = Color(nsColor: fg)
        if theme == .paper {
            surface = Color(nsColor: rgb(dark ? 0x171716 : 0xFAFAFA)); raised = Color(nsColor: rgb(dark ? 0x1E1E1D : 0xFFFFFF))
            fill = Color(nsColor: rgb(dark ? 0x212120 : 0xF3F3F3)); selected = Color(nsColor: rgb(dark ? 0x2C2C2B : 0xEBEBEB))
            line = Color(nsColor: rgb(contrast ? (dark ? 0x696968 : 0x929292) : (dark ? 0x3C3C3B : 0xDEDEDE)))
            controlLine = Color(nsColor: rgb(dark ? 0x696968 : 0x929292)); secondary = Color(nsColor: rgb(dark ? 0xA3A3A0 : 0x555555))
        } else {
            surface = mix(dark ? 0.035 : 0.018); raised = mix(dark ? 0.06 : 0)
            fill = mix(dark ? 0.075 : 0.045); selected = mix(dark ? 0.12 : 0.085)
            line = mix(contrast ? 0.55 : (dark ? 0.22 : 0.16)); controlLine = mix(0.55); secondary = mix(dark ? 0.68 : 0.72)
        }
        danger = Color(nsColor: rgb(dark ? 0xFF8B7E : 0xAE2A1F)); dangerSoft = Color(nsColor: rgb(dark ? 0x3A2522 : 0xF9EEED))
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = PipPalette() }
extension EnvironmentValues {
    var guidePalette: PipPalette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}

enum Layout {
    static let edge: CGFloat = 24, card: CGFloat = 16, group: CGFloat = 12, control: CGFloat = 34, pill: CGFloat = 999
    static let smallRadius: CGFloat = 14, cardRadius: CGFloat = 18
    static let press: Double = 0.1
}

struct PipButton: ButtonStyle {
    var primary = false
    @Environment(\.guidePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).frame(minHeight: Layout.control)
            .foregroundStyle(primary ? palette.canvas : palette.ink)
            .background(primary ? palette.ink : palette.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? palette.ink : palette.line))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.97 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: Layout.press), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
    }
}

private struct AppButtonModifier: ViewModifier {
    var primary = false
    @ViewBuilder func body(content: Content) -> some View {
        if Edition.baseline { content } else { content.buttonStyle(PipButton(primary: primary)) }
    }
}
extension View { func guideButton(primary: Bool = false) -> some View { modifier(AppButtonModifier(primary: primary)) } }

struct PipPebble: View {
    @Environment(\.guidePalette) private var palette
    var resting = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w*0.12, y: h*0.6))
                    p.addCurve(to: CGPoint(x: w*0.52, y: h*0.12), control1: CGPoint(x: w*0.02, y: h*0.3), control2: CGPoint(x: w*0.27, y: h*0.08))
                    p.addCurve(to: CGPoint(x: w*0.9, y: h*0.58), control1: CGPoint(x: w*0.79, y: h*0.14), control2: CGPoint(x: w*0.97, y: h*0.35))
                    p.addCurve(to: CGPoint(x: w*0.51, y: h*0.9), control1: CGPoint(x: w*0.86, y: h*0.85), control2: CGPoint(x: w*0.68, y: h*0.94))
                    p.addCurve(to: CGPoint(x: w*0.12, y: h*0.6), control1: CGPoint(x: w*0.25, y: h*0.87), control2: CGPoint(x: w*0.16, y: h*0.82))
                    p.closeSubpath()
                }.fill(palette.ink)
                HStack(spacing: w*0.11) {
                    Capsule().fill(palette.canvas).frame(width: w*0.09, height: h*(resting ? 0.04 : 0.16))
                    Capsule().fill(palette.canvas).frame(width: w*0.09, height: h*(resting ? 0.04 : 0.16))
                }.offset(x: w*0.07, y: h*0.02)
            }
        }.accessibilityHidden(true)
    }
}
