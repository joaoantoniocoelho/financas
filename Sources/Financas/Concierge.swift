import SwiftUI

/// The app's voice: a concierge that greets you by name and says, in one line, what needs attention.
enum Concierge {
    static let nameKey = "userName"

    /// The name set in Settings, or on the Mac the first name of the account.
    static func displayName(stored: String) -> String? {
        let name = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        #if os(macOS)
            return NSFullUserName().split(separator: " ").first.map(String.init)
        #else
            return nil
        #endif
    }

    static func greeting(name: String?, at date: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let salutation =
            switch hour {
            case 5..<12: "Bom dia"
            case 12..<18: "Boa tarde"
            default: "Boa noite"
            }
        guard let name, !name.isEmpty else { return "\(salutation)." }
        return "\(salutation), \(name)."
    }

    /// The one thing worth knowing today: pending bills first, then the next salary.
    static func insight(pendingCount: Int, pendingTotal: Double, salaryDays: Int?, hidden: Bool) -> String {
        if pendingCount > 0 {
            let bills = pendingCount == 1 ? "1 conta pendente" : "\(pendingCount) contas pendentes"
            if hidden { return "Há \(bills) este mês." }
            return pendingCount == 1
                ? "Há 1 conta pendente, de \(AppFormat.money(pendingTotal))."
                : "Há \(bills), somando \(AppFormat.money(pendingTotal))."
        }
        if let days = salaryDays {
            switch days {
            case 0: return "O salário cai hoje."
            case 1: return "O salário cai amanhã."
            default: return "Faltam \(days) dias para o salário."
            }
        }
        return "Tudo em dia por aqui."
    }
}

extension AppStore {
    /// Today's line for the selected month.
    func conciergeInsight(hidden: Bool, referenceDate: Date = .now) -> String {
        let pending = expenses.filter { $0.status == .pending }
        return Concierge.insight(
            pendingCount: pending.count,
            pendingTotal: pending.reduce(0) { $0 + $1.amount },
            salaryDays: nextSalary(referenceDate: referenceDate)?.days,
            hidden: hidden
        )
    }
}

/// A short confirmation after something is saved. `hiddenText` is shown instead while amounts are hidden.
struct Notice: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var hiddenText: String?
    var systemImage = "checkmark.circle.fill"
}

/// Slides in when the store announces something, and leaves on its own.
struct NoticeToast: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts

    var body: some View {
        ZStack {
            if let notice = store.notice {
                Label((hideAmounts ? notice.hiddenText : nil) ?? notice.text, systemImage: notice.systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .labelStyle(NoticeLabelStyle())
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(AppBrand.forest.opacity(0.94), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .transition(.move(edge: Self.edge).combined(with: .opacity))
                    .id(notice.id)
                    .onTapGesture { store.notice = nil }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: store.notice)
    }

    // On the iPhone the tab bar owns the bottom; on the Mac the toolbar owns the top.
    #if os(iOS)
        static let alignment = Alignment.top
        private static let edge = Edge.top
    #else
        static let alignment = Alignment.bottom
        private static let edge = Edge.bottom
    #endif
}

private struct NoticeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(AppBrand.mint)
            configuration.title.lineLimit(2)
        }
    }
}
