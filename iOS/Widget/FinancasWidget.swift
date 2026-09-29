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
    /// Neutral dark graphite, close to the system's own dark widgets.
    static let graphiteTop = Color(red: 0.145, green: 0.15, blue: 0.15)
    static let graphiteBottom = Color(red: 0.10, green: 0.105, blue: 0.105)
}

private struct ShortcutsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                BrandRing(lineWidth: 2)
                    .frame(width: 13, height: 13)
                Text("Acesso rápido")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                shortcut("Resumo", "rectangle.grid.2x2.fill", "open/summary")
                shortcut("Saída", "arrow.up", "new/outflow")
                shortcut("Entrada", "arrow.down", "new/income")
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(colors: [Brand.graphiteTop, Brand.graphiteBottom], startPoint: .top, endPoint: .bottom)
                    .opacity(0.97)
                // The app's mark, large and faint, bleeding off the top right corner.
                GeometryReader { geometry in
                    BrandRing(lineWidth: 16)
                        .frame(width: geometry.size.height * 1.15, height: geometry.size.height * 1.15)
                        .opacity(0.07)
                        .position(x: geometry.size.width * 0.86, y: geometry.size.height * 0.2)
                }
            }
        }
    }

    private func shortcut(_ title: String, _ symbol: String, _ route: String) -> some View {
        Link(destination: URL(string: "financas://\(route)")!) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.mint)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                    .widgetAccentable()
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The app's mark: an open ring with a rising arrow.
private struct BrandRing: View {
    var lineWidth: CGFloat
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / 100
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Brand.mint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(lineWidth / 2)
                Path { path in
                    path.move(to: CGPoint(x: 34 * scale, y: 66 * scale))
                    path.addLine(to: CGPoint(x: 66 * scale, y: 34 * scale))
                    path.move(to: CGPoint(x: 42 * scale, y: 34 * scale))
                    path.addLine(to: CGPoint(x: 66 * scale, y: 34 * scale))
                    path.addLine(to: CGPoint(x: 66 * scale, y: 58 * scale))
                }
                .stroke(Brand.mint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            .frame(width: side, height: side)
        }
    }
}
