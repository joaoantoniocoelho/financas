import XCTest
@testable import Financas

final class ConciergeTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func at(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: hour))!
    }

    func testGreetingFollowsTheTimeOfDay() {
        XCTAssertEqual(Concierge.greeting(name: "João", at: at(hour: 8), calendar: calendar), "Bom dia, João.")
        XCTAssertEqual(Concierge.greeting(name: "João", at: at(hour: 14), calendar: calendar), "Boa tarde, João.")
        XCTAssertEqual(Concierge.greeting(name: "João", at: at(hour: 21), calendar: calendar), "Boa noite, João.")
        XCTAssertEqual(Concierge.greeting(name: "João", at: at(hour: 3), calendar: calendar), "Boa noite, João.")
        XCTAssertEqual(Concierge.greeting(name: nil, at: at(hour: 8), calendar: calendar), "Bom dia.")
    }

    func testStoredNameWins() {
        XCTAssertEqual(Concierge.displayName(stored: "  Ana  "), "Ana")
    }

    func testInsightPutsPendingBillsFirst() {
        XCTAssertEqual(Concierge.insight(pendingCount: 2, pendingTotal: 480, salaryDays: 5, hidden: false), "Há 2 contas pendentes, somando \(AppFormat.money(480)).")
        XCTAssertEqual(Concierge.insight(pendingCount: 1, pendingTotal: 90, salaryDays: nil, hidden: false), "Há 1 conta pendente, de \(AppFormat.money(90)).")
        XCTAssertEqual(Concierge.insight(pendingCount: 2, pendingTotal: 480, salaryDays: 5, hidden: true), "Há 2 contas pendentes este mês.")
    }

    func testInsightFallsBackToSalaryThenAllClear() {
        XCTAssertEqual(Concierge.insight(pendingCount: 0, pendingTotal: 0, salaryDays: 5, hidden: false), "Faltam 5 dias para o salário.")
        XCTAssertEqual(Concierge.insight(pendingCount: 0, pendingTotal: 0, salaryDays: 1, hidden: false), "O salário cai amanhã.")
        XCTAssertEqual(Concierge.insight(pendingCount: 0, pendingTotal: 0, salaryDays: 0, hidden: false), "O salário cai hoje.")
        XCTAssertEqual(Concierge.insight(pendingCount: 0, pendingTotal: 0, salaryDays: nil, hidden: false), "Tudo em dia por aqui.")
    }
}
