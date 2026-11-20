import SwiftUI

/// Visual language of the live workout, ported from the web app's `live.css`:
/// near-black stage, glass surfaces, mood-coloured ambient light, gradient
/// orb as the one primary action, big tabular numbers.
enum LV {
    static let bg = Color(red: 5 / 255, green: 5 / 255, blue: 7 / 255)
    static let surface = Color.white.opacity(0.045)
    static let surface2 = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.06)
    static let text = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let muted = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.58)
    static let faint = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.32)
    static let ember = Color(red: 1, green: 107 / 255, blue: 53 / 255)
    static let flame = Color(red: 1, green: 45 / 255, blue: 111 / 255)
    static let gold = Color(red: 1, green: 179 / 255, blue: 64 / 255)
    static let ice = Color(red: 90 / 255, green: 200 / 255, blue: 250 / 255)
    static let violet = Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)
    static let lime = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    static let danger = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let sky = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255)

    static let spring = Animation.spring(response: 0.46, dampingFraction: 0.86)
    static let bounce = Animation.spring(response: 0.42, dampingFraction: 0.6)

    /// Hero numbers: white → gold → ember → flame.
    static let heroGradient = LinearGradient(
        colors: [.white, gold, ember, flame],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Screen mood: drives the ambient light, rings and the orb gradient.
enum LiveMood: Equatable {
    case active, rest, done, paused

    var glow: Color {
        switch self {
        case .active: return LV.ember
        case .rest: return LV.ice
        case .done: return LV.lime
        case .paused: return Color(white: 0.56)
        }
    }

    var glow2: Color {
        switch self {
        case .active: return LV.flame
        case .rest: return LV.violet
        case .done: return LV.ice
        case .paused: return Color(white: 0.28)
        }
    }

    var cta: LinearGradient {
        switch self {
        case .active, .paused:
            return LinearGradient(colors: [LV.gold, LV.ember, LV.flame], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rest:
            return LinearGradient(colors: [Color(red: 165 / 255, green: 243 / 255, blue: 252 / 255), LV.ice, LV.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .done:
            return LinearGradient(colors: [Color(red: 187 / 255, green: 247 / 255, blue: 208 / 255), LV.lime, LV.sky], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Two slow blobs of mood-coloured light behind everything.
struct LiveAmbient: View {
    let mood: LiveMood
    @State private var drift = false

    var body: some View {
        ZStack {
            LV.bg
            RadialGradient(colors: [mood.glow.opacity(0.22), .clear], center: UnitPoint(x: 0.3, y: 0.18), startRadius: 0, endRadius: 320)
                .offset(x: drift ? 14 : -14, y: drift ? 10 : -8)
            RadialGradient(colors: [mood.glow2.opacity(0.16), .clear], center: UnitPoint(x: 0.75, y: 0.86), startRadius: 0, endRadius: 360)
                .offset(x: drift ? -12 : 12, y: drift ? -10 : 10)
        }
        .blur(radius: 28)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.9), value: mood)
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

extension View {
    /// Small uppercase label with wide tracking (`.lv-caps`).
    func lvCaps(_ color: Color = LV.muted) -> some View {
        font(.system(size: 11, weight: .semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Glass surface (`.lv-glass`).
    func lvGlass<S: Shape>(_ shape: S) -> some View {
        background(Material.ultraThinMaterial.opacity(0.35), in: shape)
            .background(LV.surface, in: shape)
            .overlay(shape.stroke(LV.stroke, lineWidth: 1))
    }
}

/// Press feedback: springy shrink.
struct LVPress: ButtonStyle {
    var scale: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(LV.bounce, value: configuration.isPressed)
    }
}

/// Glass circle icon button (top bar, side controls).
struct LVIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(LV.text)
                .frame(width: size, height: size)
                .lvGlass(Circle())
        }
        .buttonStyle(LVPress())
        .accessibilityLabel(Text(label))
    }
}

/// Rounded pill (adjust rest, chips, actions); `on` = mood tinted.
struct LVPill<Content: View>: View {
    var on = false
    var glow: Color = LV.ember
    var height: CGFloat = 44
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { content }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LV.text)
                .padding(.horizontal, 16)
                .frame(height: height)
                .background(on ? glow.opacity(0.22) : LV.surface, in: Capsule())
                .overlay(Capsule().stroke(on ? glow.opacity(0.55) : LV.stroke, lineWidth: 1))
        }
        .buttonStyle(LVPress())
    }
}

/// Full-width gradient call to action.
struct LVCta<Content: View>: View {
    var mood: LiveMood = .active
    var height: CGFloat = 56
    let action: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(mood.cta, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
                .shadow(color: mood.glow.opacity(enabled ? 0.45 : 0), radius: 16, y: 10)
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(LVPress(scale: 0.97))
    }
}

/// The big round primary action; tap it or swipe it up.
struct LVOrb<Content: View>: View {
    let mood: LiveMood
    var size: CGFloat = 96
    var label: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var lift: CGFloat = 0
    @State private var fired = false

    var body: some View {
        content
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(mood.cta, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            .background(Circle().stroke(mood.glow.opacity(0.45), lineWidth: 1.5).padding(-10).opacity(0.35))
            .shadow(color: mood.glow.opacity(0.5), radius: 22, y: 12)
            .offset(y: lift)
            .scaleEffect(1 + abs(lift) / 600)
            .contentShape(Circle())
            .onTapGesture { action() }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        lift = max(-90, min(0, value.translation.height))
                        if lift < -70 && !fired {
                            fired = true
                            action()
                        }
                    }
                    .onEnded { _ in
                        fired = false
                        withAnimation(LV.bounce) { lift = 0 }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Progress ring: gradient arc with a glow and a glowing knob at the tip.
struct LVRing<Content: View>: View {
    var size: CGFloat
    var stroke: CGFloat = 14
    var progress: Double
    var from: Color
    var to: Color
    @ViewBuilder let content: Content

    var body: some View {
        let p = max(0, min(1, progress))
        let r = (size - stroke) / 2 - 6
        ZStack {
            Circle()
                .stroke(.white.opacity(0.07), lineWidth: stroke)
                .frame(width: r * 2, height: r * 2)
            Circle()
                .trim(from: 0, to: p)
                .stroke(LinearGradient(colors: [from, to], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: r * 2, height: r * 2)
                .shadow(color: from.opacity(0.7), radius: 10)
            if p > 0.005 && p < 0.999 {
                let angle = p * 2 * .pi - .pi / 2
                Circle()
                    .fill(.white)
                    .frame(width: stroke * 0.55, height: stroke * 0.55)
                    .shadow(color: .white.opacity(0.9), radius: 6)
                    .offset(x: r * cos(angle), y: r * sin(angle))
            }
            VStack(spacing: 0) { content }
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.3), value: p)
    }
}

/// Story-style progress: one thin segment per exercise.
struct LVSegments: View {
    let session: LiveSession
    let mood: LiveMood

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { i, e in
                let planned = max(e.plannedSets, e.item.sets.count, 1)
                let closed = e.status == .done || e.status == .skipped
                let fill = closed ? 1 : Double(e.item.sets.count) / Double(planned)
                let isCurrent = i == session.current
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(e.status == .skipped
                                  ? AnyShapeStyle(Color.white.opacity(0.25))
                                  : isCurrent
                                    ? AnyShapeStyle(LinearGradient(colors: [mood.glow, mood.glow2], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(Color.white.opacity(0.8)))
                            .frame(width: geo.size.width * max(fill, isCurrent ? 0.06 : 0))
                            .shadow(color: isCurrent ? mood.glow : .clear, radius: 4)
                    }
                }
                .frame(height: 3)
            }
        }
        .animation(LV.spring, value: session.exercises.map(\.item.sets.count))
    }
}

/// Set dots: done (white check dot), now (wide glowing), to go (dim).
struct LVDots: View {
    let done: Int
    let total: Int
    let mood: LiveMood

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, done, 1), id: \.self) { i in
                Capsule()
                    .fill(i < done
                          ? AnyShapeStyle(LV.lime)
                          : i == done
                            ? AnyShapeStyle(LinearGradient(colors: [mood.glow, mood.glow2], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.2)))
                    .frame(width: i == done ? 24 : 8, height: 8)
                    .shadow(color: i == done ? mood.glow : .clear, radius: 5)
            }
        }
        .animation(LV.spring, value: done)
    }
}

/// Uppercase gradient badge (superset, combo).
struct LVBadge: View {
    let text: Text
    let colors: [Color]

    var body: some View {
        text
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
    }
}

/// Sheet chrome shared by every live sheet.
extension View {
    func lvSheet(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground {
                LinearGradient(colors: [Color(red: 38 / 255, green: 38 / 255, blue: 44 / 255), Color(red: 22 / 255, green: 22 / 255, blue: 26 / 255)],
                               startPoint: .top, endPoint: .bottom)
            }
            .preferredColorScheme(.dark)
    }
}
