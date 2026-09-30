#if os(macOS)
import AppKit
#endif
import SwiftUI

private struct CompactMenuDismissKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var compactMenuDismiss: () -> Void {
        get { self[CompactMenuDismissKey.self] }
        set { self[CompactMenuDismissKey.self] = newValue }
    }
}

struct CompactActionMenu<Content: View>: View {
    @State private var presented = false
    @ViewBuilder let content: () -> Content
    #if os(iOS)
    var body: some View {
        Menu { content() } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).accessibilityLabel("Mais ações")
    }
    #else
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless).pointerCursor().help("Mais ações")
        .popover(isPresented: $presented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 2) { content() }
                .padding(6).frame(minWidth: 190, alignment: .leading)
                .environment(\.compactMenuDismiss, { presented = false })
        }
    }
    #endif
}

struct CompactMenuItem: View {
    @Environment(\.compactMenuDismiss) private var dismiss
    let title: String; let role: ButtonRole?; let action: () -> Void
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) { self.title = title; self.role = role; self.action = action }
    var body: some View {
        #if os(iOS)
        Button(title, role: role, action: action)
        #else
        Group {
            if let role { Button(title, role: role) { dismiss(); action() } }
            else { Button(title) { dismiss(); action() } }
        }.buttonStyle(.borderless).pointerCursor().frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

/// The mark on a 100-unit artboard, y down: a fine open ring, gap at the top right, and a small rising
/// chart whose last point sits in the gap, like the current month. The splash, the app icon
/// (scripts/generate-icon.swift) and the widget draw from these same numbers.
enum MarkGeometry {
    static let center = CGPoint(x: 50, y: 50)
    static let radius: CGFloat = 34
    static let chart: [CGPoint] = [CGPoint(x: 27, y: 64), CGPoint(x: 41, y: 50), CGPoint(x: 51, y: 58), CGPoint(x: 74, y: 26)]
    static let dotRadius: CGFloat = 4.2
    static let haloRadius: CGFloat = 8.5
    static let stroke: CGFloat = 2.6

    /// Maps an artboard point into `rect` (a square).
    static func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x / 100 * rect.width, y: rect.minY + p.y / 100 * rect.height)
    }

    /// From 3 o'clock clockwise round to 12 o'clock.
    static func ring(in rect: CGRect) -> Path {
        Path { $0.addArc(center: point(center, in: rect), radius: radius / 100 * rect.width, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: false) }
    }

    static func chartPath(in rect: CGRect) -> Path {
        Path { $0.addLines(chart.map { point($0, in: rect) }) }
    }

    static func dot(in rect: CGRect, radius r: CGFloat = dotRadius) -> Path {
        let c = point(chart[chart.count - 1], in: rect), size = r / 100 * rect.width
        return Path(ellipseIn: CGRect(x: c.x - size, y: c.y - size, width: size * 2, height: size * 2))
    }
}

#if os(macOS)
extension AppBrand {
    /// Template artwork lets macOS choose the correct color for the menu bar.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // The ring spans 15 pt; strokes stay at a legible 1.3 pt.
            let rect = CGRect(x: 9 - 7.5 / 0.68, y: 9 - 7.5 / 0.68, width: 15 / 0.68, height: 15 / 0.68)
            let context = NSGraphicsContext.current!.cgContext
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(1.3)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(MarkGeometry.ring(in: rect).cgPath)
            context.addPath(MarkGeometry.chartPath(in: rect).cgPath)
            context.strokePath()
            context.addPath(MarkGeometry.dot(in: rect, radius: 7).cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Finanças"
        return image
    }()
}
#endif

/// The mark on its deep green tile.
struct BrandMark: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let rect = CGRect(x: side * 0.09, y: side * 0.09, width: side * 0.82, height: side * 0.82)
            let stroke = StrokeStyle(lineWidth: max(side * 0.028, 1.2), lineCap: .round, lineJoin: .round)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(AppBrand.forest)
                MarkGeometry.ring(in: rect).stroke(AppBrand.mint, style: stroke)
                MarkGeometry.chartPath(in: rect).stroke(AppBrand.mint, style: stroke)
                MarkGeometry.dot(in: rect).fill(AppBrand.mint)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

struct BrandGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label.font(.system(size: 16, weight: .semibold))
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .brandSurface()
    }
}

struct BrandBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            AppBrand.canvas
            if !reduceTransparency {
                LinearGradient(colors: [AppBrand.accent.opacity(0.12), .clear, AppBrand.mint.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea()
    }
}

private struct BrandSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if reduceTransparency {
                shape.fill(AppBrand.surface)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.06)))
    }
}

/// Keep glass in the control layer; financial content uses quieter materials.
struct BrandGlassControls<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

private struct BrandActionStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *), !reduceTransparency {
            if prominent {
                content.buttonStyle(.glassProminent).pointerCursor()
            } else {
                content.buttonStyle(.glass).pointerCursor()
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).pointerCursor()
        } else {
            content.buttonStyle(.bordered).pointerCursor()
        }
    }
}

extension View {
    @ViewBuilder func pointerCursor() -> some View {
        #if os(macOS)
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        #else
        self
        #endif
    }

    func brandSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(BrandSurface(cornerRadius: cornerRadius))
    }

    func brandAction(prominent: Bool = false) -> some View {
        modifier(BrandActionStyle(prominent: prominent))
    }
}

struct BrandIcon: View {
    let symbol: String
    var color: Color = AppBrand.accent
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}
