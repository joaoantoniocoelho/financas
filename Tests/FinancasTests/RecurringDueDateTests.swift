import XCTest

@testable import Financas

final class RecurringDueDateTests: XCTestCase {
    func testDueDateFallsOnLastDayOfShortMonths() throws {
        var item = recurring(dueDay: 31)
        let february = BudgetMonth(id: 1, year: 2026, month: 2, initialBalance: 0, currentBalance: 0)
        XCTAssertEqual(item.dueDate(in: february), try date(2026, 2, 28))
        item.dueDay = 5
        XCTAssertEqual(item.dueDate(in: february), try date(2026, 2, 5))
        item.dueDay = nil
        XCTAssertNil(item.dueDate(in: february))
    }

    @MainActor
    func testChangedDueDayIsKeptAndMovesTheDateInTheMonth() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try Database(url: directory.appendingPathComponent("test.sqlite"), today: try date(2026, 9, 2))
        try database.saveRecurring(recurring(dueDay: 8))
        try database.createMonth(year: 2026, month: 9)
        let store = AppStore(database: database)
        let month = try XCTUnwrap(store.selectedMonth)
        var item = try XCTUnwrap(store.recurring.first)
        item.dueDay = 20
        store.save(item)
        XCTAssertEqual(try XCTUnwrap(database.recurringExpenses().first).dueDay, 20)
        XCTAssertEqual(try XCTUnwrap(store.recurring.first).dueDate(in: month), try date(2026, 9, 20))
        XCTAssertEqual(store.expenses.count, 1)
    }

    private func recurring(dueDay: Int?) -> RecurringExpense {
        RecurringExpense(
            id: 0, description: "Internet", category: "Moradia", amount: 100, dueDay: dueDay, paymentMethod: .pix,
            notes: "", active: true)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)))
    }
}
