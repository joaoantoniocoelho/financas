import SwiftUI

/// The launch animation: the last months plot themselves as a rising line on a ledger grid, and the line
/// wraps around to become the app mark (ring and arrow). The greeting and wordmark settle in below.
struct SplashView: View {
    /// Matches the iOS launch screen color (LaunchBackground), so the hand-off is seamless.
    static let launchBackground = Color(red: 0.015, green: 0.17, blue: 0.12)
    /// How long the animation takes to finish; the launch screen waits a little longer before leaving.
    static let duration: TimeInterval = 2.35
    /// Debug builds only: FINANCAS_SPLASH_AT=1.2 holds the splash at that moment, for screenshots.
    static let frozenTime: TimeInterval? = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FINANCAS_SPLASH_AT"].flatMap(TimeInterval.init)
        #else
        nil
        #endif
    }()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Concierge.nameKey) private var userName = ""
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = Self.frozenTime ?? (reduceMotion ? Self.duration : start.map { context.date.timeIntervalSince($0) } ?? 0)
            GeometryReader { geometry in
                let plot = SplashPlot(size: geometry.size)
                ZStack(alignment: .bottomLeading) {
                    background(t)
                    Canvas { context, _ in plot.draw(in: &context, at: t) }
                    wordmark(t)
                        .padding(.horizontal, 28)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 28)
                }
            }
        }
        #if os(iOS)
        .ignoresSafeArea()
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finanças")
        .onAppear { if start == nil { start = .now } }
    }

    private func background(_ t: Double) -> some View {
        ZStack {
            Self.launchBackground
            LinearGradient(
                colors: [Color(red: 0.012, green: 0.10, blue: 0.075), Color(red: 0.015, green: 0.20, blue: 0.14), Color(red: 0.008, green: 0.12, blue: 0.085)],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(Splash.phase(t, 0, 0.5))
        }
    }

    private func wordmark(_ t: Double) -> some View {
        let greeting = Concierge.greeting(name: Concierge.displayName(stored: userName))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return VStack(alignment: .leading, spacing: 0) {
            Text(greeting.uppercased())
                .font(.caption.weight(.semibold)).tracking(2.2)
                .foregroundStyle(AppBrand.mint)
                .rise(Splash.phase(t, 1.35, 1.75))
            Text("Finanças")
                .font(.system(size: 50, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .padding(.top, 6)
                .rise(Splash.phase(t, 1.45, 1.9))
            Text("Um mês de cada vez.")
                .font(.system(size: 19, design: .serif)).italic()
                .foregroundStyle(.white.opacity(0.62))
                .rise(Splash.phase(t, 1.6, 2.05))
            Label("Seus dados ficam neste dispositivo", systemImage: "lock.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 28)
                .opacity(Splash.phase(t, 1.8, 2.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func rise(_ progress: Double) -> some View {
        opacity(progress).offset(y: (1 - progress) * 14)
    }
}

/// Timing helpers: every element runs on the same clock, so the choreography stays in step.
enum Splash {
    /// 0 before `from`, 1 after `to`, eased in between.
    static func phase(_ t: Double, _ from: Double, _ to: Double) -> Double {
        easeOut(linear(t, from, to))
    }

    static func linear(_ t: Double, _ from: Double, _ to: Double) -> Double {
        min(max((t - from) / (to - from), 0), 1)
    }

    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
}

/// The geometry of the chart and the mark for a given screen size, and how to draw them at time `t`.
struct SplashPlot {
    /// Rising, with the dips of a real year.
    static let values: [Double] = [0.04, 0.2, 0.12, 0.3, 0.24, 0.46, 0.38, 0.6, 0.76]

    let size: CGSize
    let center: CGPoint
    let radius: CGFloat
    let markStroke: CGFloat
    let baseline: CGFloat
    let months: [(point: CGPoint, label: String, isCurrent: Bool)]
    /// The chart as a polyline (the last curve sampled), with cumulative lengths for partial drawing.
    let line: [CGPoint]
    let lengths: [CGFloat]

    // Timeline, in seconds.
    static let grid = (0.0, 0.7)
    static let chart = (0.2, 1.3)
    static let ring = (1.3, 1.8)
    static let arrow = (1.72, 2.05)
    static let glow = (1.78, 2.35)

    init(size: CGSize, now: Date = .now, calendar: Calendar = .current) {
        self.size = size
        let w = size.width, h = size.height
        let radius = min(w * 0.17, h * 0.09, 88)
        let center = CGPoint(x: w * 0.72, y: h * 0.25)
        let baseline = h * 0.6
        let bottom = CGPoint(x: center.x, y: center.y + radius)
        self.radius = radius
        self.center = center
        self.baseline = baseline
        markStroke = radius * MarkGeometry.stroke / MarkGeometry.radius // the icon's proportions

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "LLL"
        let count = Self.values.count
        let left = w * 0.06, right = bottom.x - radius * 1.15
        months = Self.values.enumerated().map { index, value in
            let x = left + (right - left) * CGFloat(index) / CGFloat(count - 1)
            let y = baseline - CGFloat(value) * (baseline - bottom.y)
            let date = calendar.date(byAdding: .month, value: index - (count - 1), to: now) ?? now
            let label = formatter.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
            return (CGPoint(x: x, y: y), label, index == count - 1)
        }

        // Enter from off screen, run through every month, then ease into the ring's lowest point, level.
        var points = [CGPoint(x: -12, y: months[0].point.y + 10)] + months.map(\.point)
        let last = months[count - 1].point
        let c1 = CGPoint(x: last.x + (bottom.x - last.x) * 0.45, y: last.y - (last.y - bottom.y) * 1.1)
        let c2 = CGPoint(x: bottom.x - radius * 0.55, y: bottom.y)
        for step in 1...24 {
            let s = CGFloat(step) / 24
            let a = pow(1 - s, 3), b = 3 * pow(1 - s, 2) * s, c = 3 * (1 - s) * s * s, d = s * s * s
            points.append(CGPoint(x: a * last.x + b * c1.x + c * c2.x + d * bottom.x,
                                  y: a * last.y + b * c1.y + c * c2.y + d * bottom.y))
        }
        line = points
        var total: CGFloat = 0
        lengths = points.indices.map { index in
            if index > 0 { total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y) }
            return total
        }
    }

    /// Converts a point from the mark's 100-unit artboard (see MarkGeometry).
    private func icon(_ p: CGPoint) -> CGPoint {
        let scale = radius / MarkGeometry.radius
        return CGPoint(x: center.x + (p.x - MarkGeometry.center.x) * scale, y: center.y + (p.y - MarkGeometry.center.y) * scale)
    }

    private func arc(from: Double, to: Double) -> Path {
        Path { path in
            let steps = max(Int(abs(to - from) / 3), 2)
            for step in 0...steps {
                let angle = (from + (to - from) * Double(step) / Double(steps)) * .pi / 180
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    /// The chart points drawn so far, ending at the exact tip.
    private func partialLine(_ progress: Double) -> [CGPoint] {
        guard progress > 0, let total = lengths.last else { return [] }
        let target = total * progress
        var result = [line[0]]
        for index in 1..<line.count {
            if lengths[index] <= target { result.append(line[index]); continue }
            let segment = lengths[index] - lengths[index - 1]
            let f = segment > 0 ? (target - lengths[index - 1]) / segment : 0
            result.append(CGPoint(x: line[index - 1].x + (line[index].x - line[index - 1].x) * f,
                                  y: line[index - 1].y + (line[index].y - line[index - 1].y) * f))
            break
        }
        return result
    }

    /// When the drawing tip reaches a month, as a share of the chart.
    private func share(ofMonth index: Int) -> Double {
        Double(lengths[index + 1] / (lengths.last ?? 1))
    }

    func draw(in context: inout GraphicsContext, at t: Double) {
        let mint = AppBrand.mint
        let chartProgress = Splash.linear(t, Self.chart.0, Self.chart.1)
        let gridProgress = Splash.phase(t, Self.grid.0, Self.grid.1)

        // Ledger grid: rules drawn in from the left.
        let top = center.y - radius * 1.6
        var y = baseline
        var row = 0
        while y > top {
            let reach = size.width * gridProgress
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: reach, y: y)) },
                           with: .color(mint.opacity(row == 0 ? 0.16 : 0.055)), lineWidth: row == 0 ? 1 : 0.6)
            y -= 38; row += 1
        }

        // Month ticks and labels, lit as the line passes.
        for (index, month) in months.enumerated() {
            let lit = Splash.phase(chartProgress, share(ofMonth: index) - 0.04, share(ofMonth: index) + 0.06)
            context.stroke(Path { $0.move(to: CGPoint(x: month.point.x, y: baseline)); $0.addLine(to: CGPoint(x: month.point.x, y: baseline + 6)) },
                           with: .color(mint.opacity(0.25 * gridProgress)), lineWidth: 1)
            context.stroke(Path { $0.move(to: month.point); $0.addLine(to: CGPoint(x: month.point.x, y: baseline)) },
                           with: .color(mint.opacity(0.07 * lit)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            var label = context.resolve(Text(month.label).font(.system(size: 9, weight: .semibold, design: .monospaced)))
            label.shading = .color(month.isCurrent ? mint.opacity(lit) : .white.opacity(0.18 + 0.22 * lit))
            context.draw(label, at: CGPoint(x: month.point.x, y: baseline + 18))
        }

        // The chart: soft area underneath, a glow, then the line itself.
        let drawn = partialLine(chartProgress)
        let ring = Splash.easeInOut(Splash.linear(t, Self.ring.0, Self.ring.1))
        if drawn.count > 1 {
            var area = Path()
            area.move(to: CGPoint(x: drawn[0].x, y: baseline))
            drawn.forEach { area.addLine(to: $0) }
            area.addLine(to: CGPoint(x: drawn[drawn.count - 1].x, y: baseline))
            area.closeSubpath()
            // Fades back as the mark forms, so it doesn't leave a column under the ring.
            context.fill(area, with: .linearGradient(Gradient(colors: [mint.opacity(0.16 * (1 - 0.65 * ring)), mint.opacity(0)]),
                                                     startPoint: CGPoint(x: 0, y: center.y), endPoint: CGPoint(x: 0, y: baseline)))
            let path = Path { $0.addLines(drawn) }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.stroke(path, with: .color(mint.opacity(0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(mint), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }

        // A dot pops on each month as the line reaches it; the current month keeps a halo.
        for (index, month) in months.enumerated() {
            let reached = share(ofMonth: index)
            let pop = Splash.linear(chartProgress, reached, min(reached + 0.08, 1))
            guard pop > 0 else { continue }
            let overshoot = 1 + sin(pop * .pi) * 0.5
            let r = 3.2 * overshoot
            context.fill(Path(ellipseIn: CGRect(x: month.point.x - r, y: month.point.y - r, width: r * 2, height: r * 2)), with: .color(mint))
            context.fill(Path(ellipseIn: CGRect(x: month.point.x - 1.3, y: month.point.y - 1.3, width: 2.6, height: 2.6)), with: .color(SplashView.launchBackground))
            if month.isCurrent {
                let halo = 7 + 10 * Splash.easeOut(pop)
                context.stroke(Path(ellipseIn: CGRect(x: month.point.x - halo, y: month.point.y - halo, width: halo * 2, height: halo * 2)),
                               with: .color(mint.opacity(0.35 * (1 - pop) + 0.12)), lineWidth: 1)
            }
        }

        // Glow behind the mark once it's whole.
        let glow = Splash.phase(t, Self.glow.0, Self.glow.1)
        if glow > 0 {
            let r = radius * (1.4 + 0.9 * glow)
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [mint.opacity(0.2 * glow), mint.opacity(0)]), center: center, startRadius: 0, endRadius: r))
        }

        // The line splits at the ring's lowest point and wraps both ways, swelling to the icon's weight.
        if ring > 0 {
            let width = 2.2 + (markStroke - 2.2) * Splash.easeOut(ring)
            let style = StrokeStyle(lineWidth: width, lineCap: .round)
            context.stroke(arc(from: 90, to: 90 - 90 * ring), with: .color(mint), style: style)
            context.stroke(arc(from: 90, to: 90 + 180 * ring), with: .color(mint), style: style)
        }

        // Inside the ring, the small chart of the mark plots itself, and its last point lands in the gap.
        let inner = Splash.phase(t, Self.arrow.0, Self.arrow.1)
        if inner > 0 {
            let points = MarkGeometry.chart.map(icon)
            var segments: [CGFloat] = []
            for index in 1..<points.count { segments.append(hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)) }
            var remaining = segments.reduce(0, +) * inner
            let path = Path { path in
                path.move(to: points[0])
                for index in 1..<points.count {
                    let length = segments[index - 1]
                    if remaining >= length { path.addLine(to: points[index]); remaining -= length; continue }
                    let f = remaining / length
                    path.addLine(to: CGPoint(x: points[index - 1].x + (points[index].x - points[index - 1].x) * f, y: points[index - 1].y + (points[index].y - points[index - 1].y) * f))
                    break
                }
            }
            context.stroke(path, with: .color(mint), style: StrokeStyle(lineWidth: markStroke, lineCap: .round, lineJoin: .round))
        }
        let dot = Splash.linear(t, Self.arrow.1 - 0.05, Self.arrow.1 + 0.25)
        if dot > 0 {
            let tip = icon(MarkGeometry.chart[MarkGeometry.chart.count - 1])
            let scale = radius / MarkGeometry.radius
            let r = MarkGeometry.dotRadius * scale * (1 + sin(dot * .pi) * 0.45)
            context.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)), with: .color(mint))
            let halo = MarkGeometry.haloRadius * scale * (0.6 + 0.4 * Splash.easeOut(dot))
            context.stroke(Path(ellipseIn: CGRect(x: tip.x - halo, y: tip.y - halo, width: halo * 2, height: halo * 2)),
                           with: .color(mint.opacity(0.4 * Splash.easeOut(dot))), lineWidth: max(markStroke * 0.35, 1))
        }
    }
}
