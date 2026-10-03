import Foundation
import SwiftUI

private struct HideAmountsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hideAmounts: Bool {
        get { self[HideAmountsKey.self] }
        set { self[HideAmountsKey.self] = newValue }
    }
}

enum IncomeStatus: String, CaseIterable, Identifiable {
    case pending = "A receber"
    case received = "Recebido"
    var id: String { rawValue }
}

enum ExpenseStatus: String, CaseIterable, Identifiable {
    case pending = "Pendente"
    case invoice = "Na fatura"
    case paid = "Pago"
    case prepaid = "Pago antecipado"
    var id: String { rawValue }
}

enum InvestmentStatus: String, CaseIterable, Identifiable {
    case pending = "Pendente"
    case completed = "Realizado"
    var id: String { rawValue }
}

enum PaymentMethod: String, CaseIterable, Identifiable {
    case card = "Cartão"
    case pix = "Débito/PIX"
    case automatic = "Débito automático"
    case cash = "Dinheiro"
    var id: String { rawValue }
}

struct BudgetMonth: Identifiable, Hashable {
    let id: Int64
    var year: Int
    var month: Int
    var initialBalance: Double
    var currentBalance: Double
    var balanceDate: Date?

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "LLLL yyyy"
        let date = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? .now
        return formatter.string(from: date).capitalized
    }
}

struct Income: Identifiable {
    var id: Int64
    var monthID: Int64
    var date: Date?
    var description: String
    var category: String
    var amount: Double
    var expectedDay: Int?
    var status: IncomeStatus
    var isFixed: Bool
}

struct RecurringExpense: Identifiable {
    var id: Int64
    var description: String
    var category: String
    var amount: Double
    var dueDay: Int?
    var paymentMethod: PaymentMethod
    var notes: String
    var active: Bool
}

struct Expense: Identifiable {
    var id: Int64
    var monthID: Int64
    var recurringID: Int64?
    var date: Date?
    var description: String
    var category: String
    var amount: Double
    var paymentMethod: PaymentMethod
    var status: ExpenseStatus
    var competenceYear: Int?
    var competenceMonth: Int?
    var notes: String
    var isRecurring: Bool
    var includedInInitialBalance: Bool = false
}

struct Investment: Identifiable {
    var id: Int64
    var monthID: Int64
    var plannedDate: Date
    var plannedAmount: Double
    var actualAmount: Double
    var status: InvestmentStatus
}

enum InvestmentAssetType: String, CaseIterable, Identifiable {
    case fund = "Fundo de investimento"
    case fixedIncome = "Renda fixa"
    case stocks = "Ações"
    case realEstate = "Fundo imobiliário"
    case currency = "Moeda estrangeira"
    case crypto = "Criptomoeda"
    case pension = "Previdência"
    case goal = "Objetivo financeiro"
    case other = "Outro"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .fund: "building.columns.fill"
        case .fixedIncome: "doc.text.fill"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .realEstate: "building.2.fill"
        case .currency: "dollarsign.arrow.circlepath"
        case .crypto: "bitcoinsign.circle.fill"
        case .pension: "figure.walk.circle.fill"
        case .goal: "airplane.departure"
        case .other: "square.stack.3d.up.fill"
        }
    }
}

/// The currency a foreign-currency investment is held in. Its balance is kept in that currency
/// and never added to the totals in reais.
enum ForeignCurrency: String, CaseIterable, Identifiable {
    case euro = "EUR"
    var id: String { rawValue }

    var name: String {
        switch self {
        case .euro: "Euro"
        }
    }

    var plural: String {
        switch self {
        case .euro: "Euros"
        }
    }

    var symbol: String {
        switch self {
        case .euro: "€"
        }
    }

    var systemImage: String {
        switch self {
        case .euro: "eurosign.circle.fill"
        }
    }
}

struct InvestmentFund: Identifiable, Hashable {
    var id: Int64
    var name: String
    var assetType: InvestmentAssetType = .fund
    var openingBalance: Double
    var currentBalance: Double
    var isEmergencyReserve: Bool
    var currency: ForeignCurrency = .euro

    /// Goals (like a trip) hold money but don't count toward the month's investment contributions.
    var countsAsInvestment: Bool { assetType != .goal }

    /// The currency the balance is in, or nil when it's in reais.
    var foreignCurrency: ForeignCurrency? { assetType == .currency ? currency : nil }
}

enum InvestmentMovementKind: String, CaseIterable, Identifiable {
    case contribution = "Aporte"
    case withdrawal = "Resgate"
    var id: String { rawValue }
}

struct InvestmentMovement: Identifiable {
    var id: Int64
    var monthID: Int64
    var fundID: Int64
    var date: Date
    var kind: InvestmentMovementKind
    var amount: Double
    var notes: String
    var balanceApplied: Bool = true
}

struct NextSalary {
    var date: Date
    var amount: Double
    var description: String
    var days: Int
}

struct DashboardTotals {
    var initialBalance = 0.0
    var fixedExpected = 0.0
    var fixedReceived = 0.0
    var extrasReceived = 0.0
    var recurringExpected = 0.0
    var recurringPaid = 0.0
    var invoice = 0.0
    var pending = 0.0
    var variable = 0.0
    var investmentsPlanned = 0.0
    var investmentsActual = 0.0

    var totalIncomeReceived: Double { fixedReceived + extrasReceived }
    var paidVariable: Double = 0.0
    var variableBudget: Double { fixedExpected - recurringExpected - investmentsPlanned }
}

enum AppFormat {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    static func money(_ value: Double, hidden: Bool = false) -> String {
        if hidden { return "R$ ••••" }
        return currency.string(from: NSNumber(value: value)) ?? "R$ 0,00"
    }

    private static let foreignFormatters: [ForeignCurrency: NumberFormatter] = Dictionary(
        uniqueKeysWithValues: ForeignCurrency.allCases.map { code in
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.locale = Locale(identifier: "pt_BR")
            f.currencyCode = code.rawValue
            f.currencySymbol = code.symbol
            return (code, f)
        })

    /// A balance in its own currency, or in reais when `currency` is nil.
    static func money(_ value: Double, in currency: ForeignCurrency?, hidden: Bool = false) -> String {
        guard let currency, let formatter = foreignFormatters[currency] else { return money(value, hidden: hidden) }
        if hidden { return "\(currency.symbol) ••••" }
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency.symbol) 0,00"
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateStyle = .short
        return f
    }()
}
