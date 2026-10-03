import SwiftUI

/// A money amount that fades in softly when it appears and cross-fades to new values.
/// Style it like any `Text` (font, weight, monospaced digits) from the outside.
struct AnimatedMoney: View {
    let value: Double
    var hidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        Text(AppFormat.money(value, hidden: hidden))
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: value)
            .opacity(visible || reduceMotion ? 1 : 0)
            .blur(radius: visible || reduceMotion ? 0 : 4)
            .onAppear {
                guard !visible else { return }
                withAnimation(.easeOut(duration: 0.45).delay(0.1)) { visible = true }
            }
    }
}

/// Cards rise and fade in one after another when a screen first appears.
private struct Entrance: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 18)
            .scaleEffect(visible || reduceMotion ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !visible else { return }
                withAnimation(
                    .spring(response: 0.55, dampingFraction: 0.82).delay(reduceMotion ? 0 : Double(order) * 0.06)
                ) {
                    visible = true
                }
            }
    }
}

extension View {
    func entrance(_ order: Int) -> some View { modifier(Entrance(order: order)) }
}

/// Deep green gradient with a soft light that drifts slowly across it, for the hero cards.
struct HeroBackground: View {
    var cornerRadius: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            LinearGradient(
                colors: [AppBrand.forest, AppBrand.evergreen], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geometry in
                let size = max(geometry.size.width, geometry.size.height)
                RadialGradient(
                    colors: [AppBrand.mint.opacity(0.28), .clear], center: .center, startRadius: 0,
                    endRadius: size * 0.55
                )
                .frame(width: size * 1.1, height: size * 1.1)
                .position(x: geometry.size.width * (drift ? 0.85 : 0.1), y: geometry.size.height * (drift ? 0.9 : -0.1))
                .blendMode(.plusLighter)
            }
            // A faint echo of the brand ring.
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(AppBrand.mint.opacity(0.10), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 170, height: 170)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 60, y: -50)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08)))
        .shadow(color: AppBrand.forest.opacity(0.22), radius: 12, y: 6)
        // Decoration only: the drifting glow and ring overflow the card, and must not catch taps
        // meant for controls around it (the filter chips sit right above these cards).
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Rows and cards shrink slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
