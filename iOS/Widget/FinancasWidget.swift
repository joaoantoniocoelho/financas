import SwiftUI
import WidgetKit

/// Home screen shortcuts. It shows no amounts on purpose: each button opens the app
/// straight into the matching form through a `financas://new/…` link.
@main
struct FinancasWidgetBundle: WidgetBundle {
    var body: some Widget { ShortcutsWidget() }
}

struct ShortcutsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FinancasShortcuts", provider: Provider()) { _ in
            ShortcutsView()
        }
        .configurationDisplayName("Atalhos")
        .description("Abra o resumo ou registre uma saída ou entrada.")
        .supportedFamilies([.systemMedium])
    }
}

private struct Entry: TimelineEntry { let date: Date }

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

private enum Brand {
    static let mint = Color(red: 0.76, green: 0.91, blue: 0.64)
    /// The app icon's deep green, so the widget sits next to it as one piece.
    static let greenTop = Color(red: 0.06, green: 0.27, blue: 0.20)
    static let greenBottom = Color(red: 0.02, green: 0.12, blue: 0.09)
}

private struct ShortcutsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                BrandRing(lineWidth: 1.4)
                    .frame(width: 15, height: 15)
                Text("ACESSO RÁPIDO")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(Brand.mint.opacity(0.9))
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                shortcut("Resumo", "rectangle.grid.2x2.fill", "open/summary")
                shortcut("Saída", "arrow.up", "new/outflow")
                shortcut("Entrada", "arrow.down", "new/income")
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    private func shortcut(_ title: String, _ symbol: String, _ route: String) -> some View {
        Link(destination: URL(string: "financas://\(route)")!) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.mint)
                    .frame(width: 46, height: 46)
                    .background(Brand.mint.opacity(0.1), in: Circle())
                    .overlay(Circle().strokeBorder(Brand.mint.opacity(0.2), lineWidth: 1))
                    .widgetAccentable()
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The app icon's deep green with the splash's ledger rules, soft light and the mark.
private struct WidgetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.greenTop, Brand.greenBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geometry in
                // Faint ledger rules and a soft light, as in the splash and the icon.
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { _ in
                        Spacer(minLength: 0)
                        Rectangle().fill(.white.opacity(0.045)).frame(height: 1)
                    }
                    Spacer(minLength: 0)
                }
                RadialGradient(colors: [Brand.mint.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: geometry.size.height * 0.8)
                    .frame(width: geometry.size.height * 1.6, height: geometry.size.height * 1.6)
                    .position(x: geometry.size.width * 0.86, y: geometry.size.height * 0.2)
                // The app's mark, large and faint, bleeding off the top right corner.
                BrandRing(lineWidth: 4)
                    .frame(width: geometry.size.height * 1.15, height: geometry.size.height * 1.15)
                    .opacity(0.1)
                    .position(x: geometry.size.width * 0.86, y: geometry.size.height * 0.2)
            }
        }
    }
}

/// The app's mark: a fine open ring whose small rising chart ends in the gap, like the current month.
/// Same numbers as MarkGeometry in the app (a 100-unit artboard, y down).
private struct BrandRing: View {
    var lineWidth: CGFloat
    private static let chart: [CGPoint] = [CGPoint(x: 27, y: 64), CGPoint(x: 41, y: 50), CGPoint(x: 51, y: 58), CGPoint(x: 74, y: 26)]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            // The ring spans the whole frame: its 68 units become `side`.
            let scale = side / 68
            let point = { (p: CGPoint) in CGPoint(x: side / 2 + (p.x - 50) * scale, y: side / 2 + (p.y - 50) * scale) }
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let tip = point(Self.chart[Self.chart.count - 1])
            let dot = max(4.2 * scale, lineWidth * 1.2)
            ZStack {
                Path { $0.addArc(center: CGPoint(x: side / 2, y: side / 2), radius: side / 2 - lineWidth / 2, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: false) }
                    .stroke(Brand.mint, style: style)
                Path { $0.addLines(Self.chart.map(point)) }
                    .stroke(Brand.mint, style: style)
                Circle().fill(Brand.mint)
                    .frame(width: dot * 2, height: dot * 2)
                    .position(tip)
            }
            .frame(width: side, height: side)
        }
    }
}
