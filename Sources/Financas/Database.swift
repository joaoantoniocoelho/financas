import Foundation

#if canImport(CSQLite)
    import CSQLite
#else
    import SQLite3
#endif

enum DatabaseError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

final class Database {
    private var handle: OpaquePointer?
    let url: URL
    private let today: Date
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL = Database.defaultURL, today: Date = .now) throws {
        self.url = url
        self.today = today
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw DatabaseError.message("Não foi possível abrir o banco SQLite.")
        }
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
        try migrateAwayFromAutomaticCardInvoices()
        try seedIfNeeded()
        try seedInvestmentFundsIfNeeded()
    }

    deinit { sqlite3_close(handle) }

    static var defaultURL: URL {
        // Demos and screenshots can point the app at another file without touching real data.
        if let path = ProcessInfo.processInfo.environment["FINANCAS_DATABASE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Financas", isDirectory: true).appendingPathComponent("financas.sqlite")
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS months (
              id INTEGER PRIMARY KEY, year INTEGER NOT NULL, month INTEGER NOT NULL,
              initial_balance REAL NOT NULL DEFAULT 0, current_balance REAL NOT NULL DEFAULT 0, balance_date TEXT,
              UNIQUE(year, month)
            );
            CREATE TABLE IF NOT EXISTS income_entries (
              id INTEGER PRIMARY KEY, month_id INTEGER NOT NULL REFERENCES months(id) ON DELETE CASCADE,
              date TEXT, description TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'Outros',
              amount REAL NOT NULL, expected_day INTEGER, status TEXT NOT NULL, is_fixed INTEGER NOT NULL DEFAULT 0,
              balance_applied INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS recurring_expenses (
              id INTEGER PRIMARY KEY, description TEXT NOT NULL, category TEXT NOT NULL,
              amount REAL NOT NULL, due_day INTEGER, payment_method TEXT NOT NULL,
              notes TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS monthly_expenses (
              id INTEGER PRIMARY KEY, month_id INTEGER NOT NULL REFERENCES months(id) ON DELETE CASCADE,
              recurring_id INTEGER REFERENCES recurring_expenses(id) ON DELETE SET NULL,
              date TEXT, description TEXT NOT NULL, category TEXT NOT NULL, amount REAL NOT NULL,
              payment_method TEXT NOT NULL, status TEXT NOT NULL,
              competence_year INTEGER, competence_month INTEGER, notes TEXT NOT NULL DEFAULT '',
              is_recurring INTEGER NOT NULL DEFAULT 0, balance_applied INTEGER NOT NULL DEFAULT 0,
              included_in_initial_balance INTEGER NOT NULL DEFAULT 0,
              excluded INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS invoice_payments (
              id INTEGER PRIMARY KEY,
              month_id INTEGER NOT NULL REFERENCES months(id) ON DELETE CASCADE,
              amount REAL NOT NULL,
              date TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS investments (
              id INTEGER PRIMARY KEY, month_id INTEGER NOT NULL REFERENCES months(id) ON DELETE CASCADE,
              planned_date TEXT NOT NULL, planned_amount REAL NOT NULL,
              actual_amount REAL NOT NULL DEFAULT 0, status TEXT NOT NULL,
              balance_applied INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS categories (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, UNIQUE(name, kind)
            );
            CREATE TABLE IF NOT EXISTS investment_funds (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE,
              opening_balance REAL NOT NULL DEFAULT 0,
              is_emergency_reserve INTEGER NOT NULL DEFAULT 0,
              counts_as_investment INTEGER NOT NULL DEFAULT 1,
              active INTEGER NOT NULL DEFAULT 1,
              asset_type TEXT NOT NULL DEFAULT 'Fundo de investimento',
              currency TEXT NOT NULL DEFAULT 'EUR'
            );
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY, value REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS investment_movements (
              id INTEGER PRIMARY KEY,
              month_id INTEGER NOT NULL REFERENCES months(id) ON DELETE CASCADE,
              fund_id INTEGER NOT NULL REFERENCES investment_funds(id) ON DELETE RESTRICT,
              date TEXT NOT NULL, kind TEXT NOT NULL, amount REAL NOT NULL,
              notes TEXT NOT NULL DEFAULT '', balance_applied INTEGER NOT NULL DEFAULT 1
            );
            """)
        if try !hasColumn("current_balance", in: "months") {
            try execute("ALTER TABLE months ADD COLUMN current_balance REAL NOT NULL DEFAULT 0")
            try execute("UPDATE months SET current_balance=initial_balance")
        }
        for table in ["income_entries", "monthly_expenses", "investments"]
        where try !hasColumn("balance_applied", in: table) {
            try execute("ALTER TABLE \(table) ADD COLUMN balance_applied INTEGER NOT NULL DEFAULT 0")
        }
        if try !hasColumn("included_in_initial_balance", in: "monthly_expenses") {
            try execute(
                "ALTER TABLE monthly_expenses ADD COLUMN included_in_initial_balance INTEGER NOT NULL DEFAULT 0")
        }
        if try !hasColumn("excluded", in: "monthly_expenses") {
            try execute("ALTER TABLE monthly_expenses ADD COLUMN excluded INTEGER NOT NULL DEFAULT 0")
        }
        if try !hasColumn("counts_as_investment", in: "investment_funds") {
            try execute("ALTER TABLE investment_funds ADD COLUMN counts_as_investment INTEGER NOT NULL DEFAULT 1")
        }
        if try !hasColumn("asset_type", in: "investment_funds") {
            try execute(
                "ALTER TABLE investment_funds ADD COLUMN asset_type TEXT NOT NULL DEFAULT 'Fundo de investimento'")
            try execute(
                "UPDATE investment_funds SET asset_type=? WHERE counts_as_investment=0 OR lower(name)=lower('Viagem')",
                bindings: [InvestmentAssetType.goal.rawValue])
        }
        if try !hasColumn("currency", in: "investment_funds") {
            try execute("ALTER TABLE investment_funds ADD COLUMN currency TEXT NOT NULL DEFAULT 'EUR'")
        }
    }

    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        var found = false
        try rows("PRAGMA table_info(\(table))") { statement in
            if text(statement, 1) == column { found = true }
        }
        return found
    }

    func execute(_ sql: String, bindings: [Any?] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            // sqlite3_prepare_v2 compiles one statement only; use exec for multi-statement migrations.
            if bindings.isEmpty, sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK { return }
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        if bindings.isEmpty, sql.contains(";") {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
        }
    }

    private func rows(_ sql: String, bindings: [Any?] = [], map: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        while sqlite3_step(statement) == SQLITE_ROW { map(statement!) }
    }

    private func bind(_ values: [Any?], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case nil: result = sqlite3_bind_null(statement, index)
            case let value as Int: result = sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Int64: result = sqlite3_bind_int64(statement, index, value)
            case let value as Double: result = sqlite3_bind_double(statement, index, value)
            case let value as Bool: result = sqlite3_bind_int(statement, index, value ? 1 : 0)
            case let value as Date:
                result = sqlite3_bind_text(statement, index, Self.iso.string(from: value), -1, transient)
            default: result = sqlite3_bind_text(statement, index, String(describing: value!), -1, transient)
            }
            guard result == SQLITE_OK else { throw lastError() }
        }
    }

    private func lastError() -> DatabaseError {
        DatabaseError.message(String(cString: sqlite3_errmsg(handle)))
    }

    /// Dates are stored as calendar days ("2026-09-26") in the user's time zone. The formatter's
    /// default is UTC, which shifted days backwards in Brazil and saved late-evening entries as the next day.
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; f.timeZone = .current; return f
    }()
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let raw = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: raw)
    }
    private func optionalDate(_ statement: OpaquePointer, _ column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return Self.iso.date(from: text(statement, column))
    }
    private func optionalInt(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, column))
    }

    func months() throws -> [BudgetMonth] {
        var result: [BudgetMonth] = []
        try rows(
            "SELECT id, year, month, initial_balance, current_balance, balance_date FROM months ORDER BY year, month"
        ) { s in
            result.append(
                BudgetMonth(
                    id: sqlite3_column_int64(s, 0), year: Int(sqlite3_column_int(s, 1)),
                    month: Int(sqlite3_column_int(s, 2)), initialBalance: sqlite3_column_double(s, 3),
                    currentBalance: sqlite3_column_double(s, 4), balanceDate: optionalDate(s, 5)))
        }
        return result
    }

    @discardableResult func createMonth(year: Int, month: Int, initialBalance: Double = 0, balanceDate: Date? = nil)
        throws -> Int64
    {
        try execute(
            "INSERT INTO months(year, month, initial_balance, current_balance, balance_date) VALUES(?,?,?,?,?)",
            bindings: [year, month, initialBalance, initialBalance, balanceDate])
        let id = sqlite3_last_insert_rowid(handle)
        try instantiateRecurring(monthID: id)
        try copyFixedIncomes(to: id)
        try copyInvestmentPlans(to: id, year: year, month: month)
        return id
    }

    private func copyFixedIncomes(to monthID: Int64) throws {
        try execute(
            """
            INSERT INTO income_entries(month_id,date,description,category,amount,expected_day,status,is_fixed,balance_applied)
            SELECT ?,NULL,i.description,i.category,i.amount,i.expected_day,'A receber',1,0
            FROM income_entries i
            WHERE i.is_fixed=1
              AND i.month_id=(
                SELECT id FROM months WHERE id<>? ORDER BY year DESC,month DESC LIMIT 1
              )
              AND NOT EXISTS(
                SELECT 1 FROM income_entries existing
                WHERE existing.month_id=? AND existing.is_fixed=1
                  AND existing.description=i.description AND existing.expected_day=i.expected_day
              )
            """, bindings: [monthID, monthID, monthID])
    }

    private func copyInvestmentPlans(to monthID: Int64, year: Int, month: Int) throws {
        var plans: [(day: Int, amount: Double)] = []
        try rows(
            """
            SELECT CAST(strftime('%d',planned_date) AS INTEGER),planned_amount
            FROM investments
            WHERE month_id=(SELECT id FROM months WHERE id<>? ORDER BY year DESC,month DESC LIMIT 1)
            ORDER BY planned_date
            """, bindings: [monthID]
        ) { statement in
            plans.append((Int(sqlite3_column_int(statement, 0)), sqlite3_column_double(statement, 1)))
        }
        let calendar = Calendar(identifier: .gregorian)
        for plan in plans {
            guard let plannedDate = Self.date(year: year, month: month, day: plan.day, calendar: calendar) else {
                continue
            }
            try saveInvestment(
                Investment(
                    id: 0, monthID: monthID, plannedDate: plannedDate, plannedAmount: plan.amount, actualAmount: 0,
                    status: .pending))
        }
    }

    static let defaultMonthlyInvestmentGoal = 3000.0

    /// The goal used by months without their own investment plan.
    func monthlyInvestmentGoal() throws -> Double {
        var value = Self.defaultMonthlyInvestmentGoal
        try rows("SELECT value FROM app_settings WHERE key='monthly_investment_goal'") {
            value = sqlite3_column_double($0, 0)
        }
        return value
    }

    func setMonthlyInvestmentGoal(_ value: Double) throws {
        try execute(
            "INSERT INTO app_settings(key,value) VALUES('monthly_investment_goal',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            bindings: [value])
    }

    func updateMonth(_ month: BudgetMonth) throws {
        try execute(
            "UPDATE months SET initial_balance=?, current_balance=?, balance_date=? WHERE id=?",
            bindings: [month.initialBalance, month.currentBalance, month.balanceDate, month.id])
    }

    func deleteMonth(_ id: Int64) throws { try execute("DELETE FROM months WHERE id=?", bindings: [id]) }

    func incomes(monthID: Int64) throws -> [Income] {
        var result: [Income] = []
        try rows(
            "SELECT id,month_id,date,description,category,amount,expected_day,status,is_fixed FROM income_entries WHERE month_id=? ORDER BY COALESCE(date,''), COALESCE(expected_day,99), id",
            bindings: [monthID]
        ) { s in
            result.append(
                Income(
                    id: sqlite3_column_int64(s, 0), monthID: sqlite3_column_int64(s, 1), date: optionalDate(s, 2),
                    description: text(s, 3), category: text(s, 4), amount: sqlite3_column_double(s, 5),
                    expectedDay: optionalInt(s, 6), status: IncomeStatus(rawValue: text(s, 7)) ?? .pending,
                    isFixed: sqlite3_column_int(s, 8) != 0))
        }
        return result
    }

    func saveIncome(_ item: Income) throws {
        let oldEffect = item.id == 0 ? 0 : try incomeBalanceEffect(id: item.id)
        var savedID = item.id
        if item.id == 0 {
            try execute(
                "INSERT INTO income_entries(month_id,date,description,category,amount,expected_day,status,is_fixed) VALUES(?,?,?,?,?,?,?,?)",
                bindings: [
                    item.monthID, item.date, item.description, item.category, item.amount, item.expectedDay,
                    item.status.rawValue, item.isFixed,
                ])
            savedID = sqlite3_last_insert_rowid(handle)
        } else {
            try execute(
                "UPDATE income_entries SET date=?,description=?,category=?,amount=?,expected_day=?,status=?,is_fixed=? WHERE id=?",
                bindings: [
                    item.date, item.description, item.category, item.amount, item.expectedDay, item.status.rawValue,
                    item.isFixed, item.id,
                ])
        }
        let newEffect = incomeBalanceEffect(item)
        try adjustBalance(monthID: item.monthID, by: newEffect - oldEffect)
        try execute("UPDATE income_entries SET balance_applied=? WHERE id=?", bindings: [newEffect != 0, savedID])
    }
    func deleteIncome(_ id: Int64) throws {
        let (monthID, effect) = try incomeBalanceRecord(id: id)
        try execute("DELETE FROM income_entries WHERE id=?", bindings: [id])
        try adjustBalance(monthID: monthID, by: -effect)
    }

    func recurringExpenses() throws -> [RecurringExpense] {
        var result: [RecurringExpense] = []
        try rows(
            "SELECT id,description,category,amount,due_day,payment_method,notes,active FROM recurring_expenses ORDER BY active DESC, description"
        ) { s in
            result.append(
                RecurringExpense(
                    id: sqlite3_column_int64(s, 0), description: text(s, 1), category: text(s, 2),
                    amount: sqlite3_column_double(s, 3), dueDay: optionalInt(s, 4),
                    paymentMethod: PaymentMethod(rawValue: text(s, 5)) ?? .pix, notes: text(s, 6),
                    active: sqlite3_column_int(s, 7) != 0))
        }
        return result
    }

    @discardableResult func saveRecurring(_ item: RecurringExpense) throws -> Int64 {
        if item.id == 0 {
            try execute(
                "INSERT INTO recurring_expenses(description,category,amount,due_day,payment_method,notes,active) VALUES(?,?,?,?,?,?,?)",
                bindings: [
                    item.description, item.category, item.amount, item.dueDay, item.paymentMethod.rawValue, item.notes,
                    item.active,
                ])
            return sqlite3_last_insert_rowid(handle)
        } else {
            try execute(
                "UPDATE recurring_expenses SET description=?,category=?,amount=?,due_day=?,payment_method=?,notes=?,active=? WHERE id=?",
                bindings: [
                    item.description, item.category, item.amount, item.dueDay, item.paymentMethod.rawValue, item.notes,
                    item.active, item.id,
                ])
            return item.id
        }
    }
    func deleteRecurring(_ id: Int64) throws {
        try execute("DELETE FROM recurring_expenses WHERE id=?", bindings: [id])
    }

    func instantiateRecurring(monthID: Int64) throws {
        try execute(
            """
            INSERT INTO monthly_expenses(month_id,recurring_id,description,category,amount,payment_method,status,notes,is_recurring)
            SELECT ?,id,description,category,amount,payment_method,'Pendente',notes,1
            FROM recurring_expenses r WHERE active=1
              AND NOT EXISTS(SELECT 1 FROM monthly_expenses m WHERE m.month_id=? AND m.recurring_id=r.id)
            """, bindings: [monthID, monthID])
    }

    func expenses(monthID: Int64) throws -> [Expense] {
        var result: [Expense] = []
        try rows(
            "SELECT id,month_id,recurring_id,date,description,category,amount,payment_method,status,competence_year,competence_month,notes,is_recurring,included_in_initial_balance FROM monthly_expenses WHERE month_id=? AND excluded=0 ORDER BY is_recurring DESC, COALESCE(date,''), description",
            bindings: [monthID]
        ) { s in
            result.append(
                Expense(
                    id: sqlite3_column_int64(s, 0), monthID: sqlite3_column_int64(s, 1),
                    recurringID: sqlite3_column_type(s, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 2),
                    date: optionalDate(s, 3), description: text(s, 4), category: text(s, 5),
                    amount: sqlite3_column_double(s, 6), paymentMethod: PaymentMethod(rawValue: text(s, 7)) ?? .pix,
                    status: ExpenseStatus(rawValue: text(s, 8)) ?? .pending, competenceYear: optionalInt(s, 9),
                    competenceMonth: optionalInt(s, 10), notes: text(s, 11),
                    isRecurring: sqlite3_column_int(s, 12) != 0,
                    includedInInitialBalance: sqlite3_column_int(s, 13) != 0))
        }
        return result
    }

    func saveExpenseBatch(_ items: [Expense]) throws {
        guard !items.isEmpty, items.count <= 30,
            items.allSatisfy({
                $0.id == 0 && !$0.isRecurring && $0.amount.isFinite && $0.amount > 0
                    && !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw DatabaseError.message("Não consegui entender essa lista de gastos. Tente de novo.")
        }
        try execute("SAVEPOINT expense_batch")
        do {
            for item in items { try saveExpense(item) }
            try execute("RELEASE SAVEPOINT expense_batch")
        } catch {
            try? execute("ROLLBACK TO SAVEPOINT expense_batch")
            try? execute("RELEASE SAVEPOINT expense_batch")
            throw error
        }
    }

    func saveExpense(_ newItem: Expense) throws {
        var item = newItem
        if item.id == 0 && !item.isRecurring {
            item.status = item.paymentMethod == .card ? .invoice : .paid
        }
        let oldEffect = item.id == 0 ? 0 : try expenseBalanceEffect(id: item.id)
        var savedID = item.id
        if item.id == 0 {
            try execute(
                "INSERT INTO monthly_expenses(month_id,recurring_id,date,description,category,amount,payment_method,status,competence_year,competence_month,notes,is_recurring,included_in_initial_balance) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                bindings: [
                    item.monthID, item.recurringID, item.date, item.description, item.category, item.amount,
                    item.paymentMethod.rawValue, item.status.rawValue, item.competenceYear, item.competenceMonth,
                    item.notes, item.isRecurring, item.includedInInitialBalance,
                ])
            savedID = sqlite3_last_insert_rowid(handle)
        } else {
            try execute(
                "UPDATE monthly_expenses SET date=?,description=?,category=?,amount=?,payment_method=?,status=?,competence_year=?,competence_month=?,notes=?,included_in_initial_balance=? WHERE id=?",
                bindings: [
                    item.date, item.description, item.category, item.amount, item.paymentMethod.rawValue,
                    item.status.rawValue, item.competenceYear, item.competenceMonth, item.notes,
                    item.includedInInitialBalance, item.id,
                ])
        }
        let newEffect = expenseBalanceEffect(item)
        try adjustBalance(monthID: item.monthID, by: newEffect - oldEffect)
        try execute("UPDATE monthly_expenses SET balance_applied=? WHERE id=?", bindings: [newEffect != 0, savedID])
    }

    func deleteExpense(_ id: Int64) throws {
        let (monthID, effect) = try expenseBalanceRecord(id: id)
        var recurring = false
        try rows("SELECT is_recurring FROM monthly_expenses WHERE id=?", bindings: [id]) {
            recurring = sqlite3_column_int($0, 0) != 0
        }
        if recurring {
            try execute("UPDATE monthly_expenses SET excluded=1,balance_applied=0 WHERE id=?", bindings: [id])
        } else {
            try execute("DELETE FROM monthly_expenses WHERE id=?", bindings: [id])
        }
        try adjustBalance(monthID: monthID, by: -effect)
    }
    func invoicePrepaidAmount(monthID: Int64) throws -> Double {
        var total = 0.0
        try rows("SELECT COALESCE(SUM(amount),0) FROM invoice_payments WHERE month_id=?", bindings: [monthID]) {
            total = sqlite3_column_double($0, 0)
        }
        return total
    }

    func payInvoice(monthID: Int64, status: ExpenseStatus = .paid) throws {
        guard status == .paid || status == .prepaid else {
            throw DatabaseError.message("Esse gasto não está na fatura, então não dá para quitá-lo por aqui.")
        }
        var total = 0.0
        let prepaid = try invoicePrepaidAmount(monthID: monthID)
        try rows(
            "SELECT COALESCE(SUM(amount),0) FROM monthly_expenses WHERE month_id=? AND status='Na fatura' AND balance_applied=0",
            bindings: [monthID]
        ) { total = sqlite3_column_double($0, 0) }
        try execute(
            "UPDATE monthly_expenses SET status=?, balance_applied=1 WHERE month_id=? AND status='Na fatura'",
            bindings: [status.rawValue, monthID])
        try execute("DELETE FROM invoice_payments WHERE month_id=?", bindings: [monthID])
        try adjustBalance(monthID: monthID, by: -(total - prepaid))
    }

    func prepayInvoice(monthID: Int64, amount: Double) throws {
        guard amount > 0 else { throw DatabaseError.message("Qual é o valor? Ele precisa ser maior que zero.") }
        var total = 0.0
        try rows(
            "SELECT COALESCE(SUM(amount),0) FROM monthly_expenses WHERE month_id=? AND status='Na fatura' AND balance_applied=0",
            bindings: [monthID]
        ) { total = sqlite3_column_double($0, 0) }
        let prepaid = try invoicePrepaidAmount(monthID: monthID)
        let remaining = total - prepaid
        guard amount <= remaining + 0.005 else {
            throw DatabaseError.message("Esse valor passa do que falta pagar na fatura. Quer ajustar?")
        }

        if abs(amount - remaining) <= 0.005 {
            try execute(
                "UPDATE monthly_expenses SET status=?, balance_applied=1 WHERE month_id=? AND status='Na fatura'",
                bindings: [ExpenseStatus.prepaid.rawValue, monthID])
            try execute("DELETE FROM invoice_payments WHERE month_id=?", bindings: [monthID])
        } else {
            try execute(
                "INSERT INTO invoice_payments(month_id,amount,date) VALUES(?,?,?)", bindings: [monthID, amount, today])
        }
        try adjustBalance(monthID: monthID, by: -amount)
    }

    func investments(monthID: Int64) throws -> [Investment] {
        var result: [Investment] = []
        try rows(
            "SELECT id,month_id,planned_date,planned_amount,actual_amount,status FROM investments WHERE month_id=? ORDER BY planned_date",
            bindings: [monthID]
        ) { s in
            result.append(
                Investment(
                    id: sqlite3_column_int64(s, 0), monthID: sqlite3_column_int64(s, 1),
                    plannedDate: optionalDate(s, 2) ?? .now, plannedAmount: sqlite3_column_double(s, 3),
                    actualAmount: sqlite3_column_double(s, 4),
                    status: InvestmentStatus(rawValue: text(s, 5)) ?? .pending))
        }
        return result
    }
    func saveInvestment(_ item: Investment) throws {
        let oldEffect = item.id == 0 ? 0 : try investmentBalanceEffect(id: item.id)
        var savedID = item.id
        if item.id == 0 {
            try execute(
                "INSERT INTO investments(month_id,planned_date,planned_amount,actual_amount,status) VALUES(?,?,?,?,?)",
                bindings: [item.monthID, item.plannedDate, item.plannedAmount, item.actualAmount, item.status.rawValue])
            savedID = sqlite3_last_insert_rowid(handle)
        } else {
            try execute(
                "UPDATE investments SET planned_date=?,planned_amount=?,actual_amount=?,status=? WHERE id=?",
                bindings: [item.plannedDate, item.plannedAmount, item.actualAmount, item.status.rawValue, item.id])
        }
        let newEffect = investmentBalanceEffect(item)
        try adjustBalance(monthID: item.monthID, by: newEffect - oldEffect)
        try execute("UPDATE investments SET balance_applied=? WHERE id=?", bindings: [newEffect != 0, savedID])
    }
    func deleteInvestment(_ id: Int64) throws {
        let (monthID, effect) = try investmentBalanceRecord(id: id)
        try execute("DELETE FROM investments WHERE id=?", bindings: [id])
        try adjustBalance(monthID: monthID, by: -effect)
    }

    func investmentFunds() throws -> [InvestmentFund] {
        var result: [InvestmentFund] = []
        try rows(
            """
            SELECT f.id,f.name,f.opening_balance,f.is_emergency_reserve,f.asset_type,
                   f.opening_balance + COALESCE(SUM(CASE m.kind WHEN 'Aporte' THEN m.amount ELSE -m.amount END),0),
                   f.currency
            FROM investment_funds f
            LEFT JOIN investment_movements m ON m.fund_id=f.id
            WHERE f.active=1
            GROUP BY f.id
            ORDER BY f.is_emergency_reserve DESC,f.id
            """
        ) { s in
            result.append(
                InvestmentFund(
                    id: sqlite3_column_int64(s, 0), name: text(s, 1),
                    assetType: InvestmentAssetType(rawValue: text(s, 4)) ?? .other,
                    openingBalance: sqlite3_column_double(s, 2), currentBalance: sqlite3_column_double(s, 5),
                    isEmergencyReserve: sqlite3_column_int(s, 3) != 0,
                    currency: ForeignCurrency(rawValue: text(s, 6)) ?? .euro
                ))
        }
        return result
    }

    /// Saves a fund's details. `currentBalance` is taken as the corrected balance: the opening balance is
    /// adjusted so it holds with the existing movements, without recording a contribution or touching the account.
    func saveInvestmentFund(_ item: InvestmentFund) throws {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DatabaseError.message("Que nome damos a esse investimento?") }
        var duplicate = false
        try rows("SELECT 1 FROM investment_funds WHERE lower(name)=lower(?) AND id<>?", bindings: [name, item.id]) {
            _ in duplicate = true
        }
        guard !duplicate else {
            throw DatabaseError.message("Você já tem um investimento chamado \(name). Que tal outro nome?")
        }
        // Movements are in reais, so they can't be mixed into a balance held in another currency.
        if item.foreignCurrency != nil, item.id != 0, try movementCount(fundID: item.id) > 0 {
            throw DatabaseError.message(
                "Esse investimento tem movimentações em reais. Exclua as movimentações antes de mudá-lo para moeda estrangeira."
            )
        }
        let movements =
            item.id == 0 ? 0 : try investmentFundBalance(id: item.id) - investmentFundOpeningBalance(id: item.id)
        // Reserve coverage is measured in reais, so foreign balances stay out of it.
        let isReserve = item.isEmergencyReserve && item.foreignCurrency == nil
        let bindings: [Any?] = [
            name, item.currentBalance - movements, isReserve, item.countsAsInvestment, item.assetType.rawValue,
            item.currency.rawValue,
        ]
        if item.id == 0 {
            try execute(
                "INSERT INTO investment_funds(name,opening_balance,is_emergency_reserve,counts_as_investment,asset_type,currency) VALUES(?,?,?,?,?,?)",
                bindings: bindings)
        } else {
            try execute(
                "UPDATE investment_funds SET name=?,opening_balance=?,is_emergency_reserve=?,counts_as_investment=?,asset_type=?,currency=? WHERE id=?",
                bindings: bindings + [item.id])
        }
    }

    func deleteInvestmentFund(_ id: Int64) throws {
        guard try movementCount(fundID: id) == 0 else {
            throw DatabaseError.message(
                "Esse investimento tem movimentações registradas. Exclua as movimentações antes de excluí-lo.")
        }
        try execute("DELETE FROM investment_funds WHERE id=?", bindings: [id])
    }

    private func movementCount(fundID: Int64) throws -> Int {
        var count = 0
        try rows("SELECT COUNT(*) FROM investment_movements WHERE fund_id=?", bindings: [fundID]) {
            count = Int(sqlite3_column_int($0, 0))
        }
        return count
    }

    private func investmentFundOpeningBalance(id: Int64) throws -> Double {
        var value = 0.0
        try rows("SELECT opening_balance FROM investment_funds WHERE id=?", bindings: [id]) {
            value = sqlite3_column_double($0, 0)
        }
        return value
    }

    func investmentMovements(monthID: Int64) throws -> [InvestmentMovement] {
        var result: [InvestmentMovement] = []
        try rows(
            "SELECT id,month_id,fund_id,date,kind,amount,notes,balance_applied FROM investment_movements WHERE month_id=? ORDER BY date DESC,id DESC",
            bindings: [monthID]
        ) { s in
            result.append(
                InvestmentMovement(
                    id: sqlite3_column_int64(s, 0), monthID: sqlite3_column_int64(s, 1),
                    fundID: sqlite3_column_int64(s, 2),
                    date: optionalDate(s, 3) ?? .now,
                    kind: InvestmentMovementKind(rawValue: text(s, 4)) ?? .contribution,
                    amount: sqlite3_column_double(s, 5), notes: text(s, 6),
                    balanceApplied: sqlite3_column_int(s, 7) != 0
                ))
        }
        return result
    }

    func saveInvestmentMovement(_ item: InvestmentMovement) throws {
        guard item.amount > 0 else { throw DatabaseError.message("Qual é o valor? Ele precisa ser maior que zero.") }
        var foreign = false
        try rows(
            "SELECT 1 FROM investment_funds WHERE id=? AND asset_type=?",
            bindings: [item.fundID, InvestmentAssetType.currency.rawValue]
        ) { _ in foreign = true }
        guard !foreign else {
            throw DatabaseError.message(
                "Investimentos em moeda estrangeira não recebem aportes nem resgates. Atualize o saldo editando o investimento."
            )
        }
        let old = item.id == 0 ? nil : try investmentMovementRecord(id: item.id)
        let oldFundEffect = old.map { fundEffect(kind: $0.kind, amount: $0.amount) } ?? 0
        let newFundEffect = fundEffect(kind: item.kind, amount: item.amount)
        let available = try investmentFundBalance(id: item.fundID) - (old?.fundID == item.fundID ? oldFundEffect : 0)
        guard available + newFundEffect >= -0.000_001 else {
            throw DatabaseError.message("Esse resgate é maior que o saldo do fundo. Quer ajustar o valor?")
        }

        try execute("BEGIN")
        do {
            if let old {
                if old.balanceApplied {
                    try adjustBalance(monthID: old.monthID, by: -accountEffect(kind: old.kind, amount: old.amount))
                }
                try execute(
                    "UPDATE investment_movements SET month_id=?,fund_id=?,date=?,kind=?,amount=?,notes=?,balance_applied=? WHERE id=?",
                    bindings: [
                        item.monthID, item.fundID, item.date, item.kind.rawValue, item.amount, item.notes,
                        item.balanceApplied, item.id,
                    ])
            } else {
                try execute(
                    "INSERT INTO investment_movements(month_id,fund_id,date,kind,amount,notes,balance_applied) VALUES(?,?,?,?,?,?,?)",
                    bindings: [
                        item.monthID, item.fundID, item.date, item.kind.rawValue, item.amount, item.notes,
                        item.balanceApplied,
                    ])
            }
            if item.balanceApplied {
                try adjustBalance(monthID: item.monthID, by: accountEffect(kind: item.kind, amount: item.amount))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteInvestmentMovement(_ id: Int64) throws {
        let old = try investmentMovementRecord(id: id)
        try execute("BEGIN")
        do {
            try execute("DELETE FROM investment_movements WHERE id=?", bindings: [id])
            if old.balanceApplied {
                try adjustBalance(monthID: old.monthID, by: -accountEffect(kind: old.kind, amount: old.amount))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func investmentFundBalance(id: Int64) throws -> Double {
        var value = 0.0
        try rows(
            """
            SELECT f.opening_balance + COALESCE(SUM(CASE m.kind WHEN 'Aporte' THEN m.amount ELSE -m.amount END),0)
            FROM investment_funds f LEFT JOIN investment_movements m ON m.fund_id=f.id WHERE f.id=? GROUP BY f.id
            """, bindings: [id]
        ) { value = sqlite3_column_double($0, 0) }
        return value
    }

    private func investmentMovementRecord(id: Int64) throws -> (
        monthID: Int64, fundID: Int64, kind: InvestmentMovementKind, amount: Double, balanceApplied: Bool
    ) {
        var value: (Int64, Int64, InvestmentMovementKind, Double, Bool)?
        try rows(
            "SELECT month_id,fund_id,kind,amount,balance_applied FROM investment_movements WHERE id=?", bindings: [id]
        ) { s in
            value = (
                sqlite3_column_int64(s, 0), sqlite3_column_int64(s, 1),
                InvestmentMovementKind(rawValue: text(s, 2)) ?? .contribution, sqlite3_column_double(s, 3),
                sqlite3_column_int(s, 4) != 0
            )
        }
        guard let value else { throw DatabaseError.message("Movimentação não encontrada.") }
        return value
    }

    private func fundEffect(kind: InvestmentMovementKind, amount: Double) -> Double {
        kind == .contribution ? amount : -amount
    }
    private func accountEffect(kind: InvestmentMovementKind, amount: Double) -> Double {
        kind == .contribution ? -amount : amount
    }

    private func adjustBalance(monthID: Int64, by delta: Double) throws {
        guard abs(delta) > 0.000_001 else { return }
        try execute("UPDATE months SET current_balance=current_balance+? WHERE id=?", bindings: [delta, monthID])
    }
    private func incomeBalanceEffect(_ item: Income) -> Double { item.status == .received ? item.amount : 0 }
    private func expenseBalanceEffect(_ item: Expense) -> Double {
        !item.includedInInitialBalance && [.paid, .prepaid].contains(item.status) ? -item.amount : 0
    }
    private func investmentBalanceEffect(_ item: Investment) -> Double {
        item.status == .completed ? -item.actualAmount : 0
    }
    private func incomeBalanceEffect(id: Int64) throws -> Double {
        let (_, effect) = try incomeBalanceRecord(id: id); return effect
    }
    private func expenseBalanceEffect(id: Int64) throws -> Double {
        let (_, effect) = try expenseBalanceRecord(id: id); return effect
    }
    private func investmentBalanceEffect(id: Int64) throws -> Double {
        let (_, effect) = try investmentBalanceRecord(id: id); return effect
    }
    private func incomeBalanceRecord(id: Int64) throws -> (Int64, Double) {
        var value: (Int64, Double) = (0, 0)
        try rows("SELECT month_id,amount,status,balance_applied FROM income_entries WHERE id=?", bindings: [id]) {
            let applied = sqlite3_column_int($0, 3) != 0
            value = (
                sqlite3_column_int64($0, 0),
                applied && text($0, 2) == IncomeStatus.received.rawValue ? sqlite3_column_double($0, 1) : 0
            )
        }; return value
    }
    private func expenseBalanceRecord(id: Int64) throws -> (Int64, Double) {
        var value: (Int64, Double) = (0, 0)
        try rows("SELECT month_id,amount,status,balance_applied FROM monthly_expenses WHERE id=?", bindings: [id]) {
            let paid = [ExpenseStatus.paid.rawValue, ExpenseStatus.prepaid.rawValue].contains(text($0, 2))
            let applied = sqlite3_column_int($0, 3) != 0
            value = (sqlite3_column_int64($0, 0), paid && applied ? -sqlite3_column_double($0, 1) : 0)
        }; return value
    }
    private func investmentBalanceRecord(id: Int64) throws -> (Int64, Double) {
        var value: (Int64, Double) = (0, 0)
        try rows("SELECT month_id,actual_amount,status,balance_applied FROM investments WHERE id=?", bindings: [id]) {
            let applied = sqlite3_column_int($0, 3) != 0
            value = (
                sqlite3_column_int64($0, 0),
                applied && text($0, 2) == InvestmentStatus.completed.rawValue ? -sqlite3_column_double($0, 1) : 0
            )
        }; return value
    }

    private func seedIfNeeded() throws {
        try execute("BEGIN")
        do {
            for name in ["Moradia", "Carro", "Saúde", "Educação", "Assinaturas", "SaaS / Projetos", "Lazer", "Outros"] {
                try execute("INSERT OR IGNORE INTO categories(name,kind) VALUES(?,'recurring')", bindings: [name])
            }
            for name in [
                "Mercado", "Alimentação fora", "Lazer", "Compras", "Transporte/Uber", "Pets", "Presentes", "Viagens",
                "Outros",
            ] { try execute("INSERT OR IGNORE INTO categories(name,kind) VALUES(?,'variable')", bindings: [name]) }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func seedInvestmentFundsIfNeeded() throws {
        var count = 0
        try rows("SELECT COUNT(*) FROM investment_funds") { count = Int(sqlite3_column_int($0, 0)) }
        guard count == 0 else { return }
        try execute(
            "INSERT INTO investment_funds(name,opening_balance,is_emergency_reserve) VALUES(?,?,1)",
            bindings: ["Occam Liquidez FIC FIF RF CP RL", 8532.58])
        try execute(
            "INSERT INTO investment_funds(name,opening_balance,is_emergency_reserve) VALUES(?,?,0)",
            bindings: ["Vinland Incentivado Debêntures", 2289.43])
    }

    func replaceDatabase(with source: URL) throws {
        guard source.standardizedFileURL != url.standardizedFileURL else { return }
        var candidate: OpaquePointer?
        guard sqlite3_open_v2(source.path, &candidate, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(candidate)
            throw DatabaseError.message("O arquivo selecionado não é um banco SQLite válido.")
        }
        var check: OpaquePointer?
        let validSchema =
            sqlite3_prepare_v2(
                candidate,
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('months','income_entries','monthly_expenses','investments')",
                -1, &check, nil) == SQLITE_OK
            && sqlite3_step(check) == SQLITE_ROW && sqlite3_column_int(check, 0) == 4
        sqlite3_finalize(check); sqlite3_close(candidate)
        guard validSchema else { throw DatabaseError.message("Esse arquivo não parece ser um backup do Finanças.") }

        let temporary = url.deletingLastPathComponent().appendingPathComponent("import-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: source, to: temporary)
        sqlite3_close(handle); handle = nil
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
                throw DatabaseError.message("Falha ao reabrir o banco atual após a importação.")
            }
            throw error
        }
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw DatabaseError.message("Não consegui ler esse backup.")
        }
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
        try migrateAwayFromAutomaticCardInvoices()
        try seedInvestmentFundsIfNeeded()
    }

    private func migrateAwayFromAutomaticCardInvoices() throws {
        try execute("CREATE TABLE IF NOT EXISTS app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        var alreadyMigrated = false
        try rows("SELECT value FROM app_metadata WHERE key='manual_card_invoice_mode_v1'") {
            alreadyMigrated = text($0, 0) == "1"
        }
        guard !alreadyMigrated else { return }
        // These were the only entries created by the former automatic rule:
        // recurring card expenses marked as invoice. The manually entered
        // statement total has no recurring_id and is intentionally preserved.
        try execute(
            "UPDATE monthly_expenses SET status='Pendente', date=NULL, balance_applied=0 WHERE recurring_id IS NOT NULL AND payment_method='Cartão' AND status='Na fatura'"
        )
        try execute("INSERT OR REPLACE INTO app_metadata(key,value) VALUES('manual_card_invoice_mode_v1','1')")
    }

    func applyDueCardInvoices(on date: Date) throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: date)
        let dueDayByRecurringID = Dictionary(
            uniqueKeysWithValues: try recurringExpenses().compactMap { item -> (Int64, Int)? in
                guard let dueDay = item.dueDay else { return nil }
                return (item.id, dueDay)
            })
        for month in try months() {
            for expense in try expenses(monthID: month.id) {
                guard expense.status == .pending, expense.paymentMethod == .card, let recurringID = expense.recurringID,
                    let dueDay = dueDayByRecurringID[recurringID]
                else { continue }
                guard let dueDate = Self.date(year: month.year, month: month.month, day: dueDay, calendar: calendar)
                else { continue }
                if let balanceDate = month.balanceDate,
                    calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: balanceDate)
                {
                    continue
                }
                guard today >= calendar.startOfDay(for: dueDate) else { continue }
                try execute(
                    "UPDATE monthly_expenses SET status='Na fatura', date=COALESCE(date,?) WHERE id=?",
                    bindings: [dueDate, expense.id])
            }
        }
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: start)
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: min(max(day, 1), range.count)))
    }
}
