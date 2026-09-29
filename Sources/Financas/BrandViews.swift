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

#if os(macOS)
extension AppBrand {
    /// Template artwork lets macOS choose the correct color for the menu bar.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 7,
                           startAngle: 90, endAngle: 360)
            ring.lineWidth = 1.7
            ring.lineCapStyle = .round
            ring.stroke()

            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 6.5, y: 6.5))
            arrow.line(to: NSPoint(x: 13, y: 13))
            arrow.move(to: NSPoint(x: 8, y: 13))
            arrow.line(to: NSPoint(x: 13, y: 13))
            arrow.line(to: NSPoint(x: 13, y: 8))
            arrow.lineWidth = 1.7
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Finanças"
        return image
    }()
}
#endif

/// A rising path within an open circle: room to grow.
struct BrandMark: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28).fill(AppBrand.forest)
                Circle().trim(from: 0, to: 0.75)
                    .stroke(AppBrand.mint, style: StrokeStyle(lineWidth: side * 0.065, lineCap: .round))
                    .padding(side * 0.22)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: side * 0.34, weight: .medium))
                    .foregroundStyle(AppBrand.mint)
            }
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
