import SwiftUI

struct ExpensesView: View {
    enum Mode: Equatable { case fixed, outflows }
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    @State private var editing: Expense?
    @State private var editingRecurring: RecurringExpense?
    @State private var filter: ExpenseFilter = .all
    @State private var outflowGrouping: OutflowGrouping = .date
    @State private var confirmInvoice = false
    @State private var showingPrepayment = false
    @State private var showingInvoice = false
    var mode: Mode = .fixed

    private struct ExpenseGroup: Identifiable {
        let category: String
        let items: [Expense]
        var id: String { category }
        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    private struct DateGroup: Identifiable {
        let date: Date?
        let items: [Expense]
        var id: Date? { date }
        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    enum ExpenseFilter: String, CaseIterable, Identifiable {
        case all = "Todos", invoice = "Na fatura", pending = "Pendentes", paid = "Pagos"; var id: String { rawValue }
    }
    private enum OutflowGrouping: String, CaseIterable, Identifiable {
        case date = "Data", category = "Categoria"
        var id: String { rawValue }
    }
    private var modeExpenses: [Expense] { store.expenses.filter { mode == .fixed ? $0.isRecurring : !$0.isRecurring } }
    var filtered: [Expense] {
        switch filter {
        case .all: return modeExpenses
        case .invoice: return modeExpenses.filter { $0.status == .invoice }
        case .pending: return modeExpenses.filter { $0.status == .pending }
        case .paid: return modeExpenses.filter { [.paid, .prepaid].contains($0.status) }
        }
    }
    private var groups: [ExpenseGroup] {
        Dictionary(grouping: filtered, by: \.category)
            .map {
                ExpenseGroup(
                    category: $0.key,
                    items: $0.value.sorted {
                        $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending
                    })
            }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }
    private var dateGroups: [DateGroup] {
        Dictionary(grouping: filtered) { $0.date.map { Calendar.current.startOfDay(for: $0) } }
            .map { DateGroup(date: $0.key, items: $0.value.sorted { $0.id > $1.id }) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        if let month = store.selectedMonth {
            content(month)
                .sheet(item: $editing) { ExpenseEditor(item: $0) }
                .sheet(isPresented: $showingInvoice) { InvoiceSheet() }
                .sheet(item: $editingRecurring) { RecurringEditor(item: $0, addToCurrentMonth: true) }
                .confirmationDialog("Quitar a fatura?", isPresented: $confirmInvoice, titleVisibility: .visible) {
                    Button("Marcar lançamentos como pagos") { store.payInvoice() }.pointerCursor()
                    Button("Cancelar", role: .cancel) {}.pointerCursor()
                } message: {
                    Text("Todos os gastos em “Na fatura” passarão para “Pago”. Nenhuma nova despesa será criada.")
                }
                .sheet(isPresented: $showingPrepayment) {
                    InvoicePrepaymentEditor(maximum: store.totals.invoice, initialAmount: store.totals.invoice) {
                        value in
                        store.prepayInvoice(amount: value)
                    }
                }
        } else {
            EmptyMonthView()
        }
    }

    /// iPhone: one scrolling column of cards, so the header never gets clipped by list insets.
    @ViewBuilder private func content(_ month: BudgetMonth) -> some View {
        if compact {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mobileHeader(month).entrance(0)
                    ChipPicker(selection: $filter, options: ExpenseFilter.allCases, title: \.rawValue).entrance(1)
                    totalCard.entrance(2)
                    if filtered.isEmpty {
                        ContentUnavailableView(
                            filter == .all ? "Nada por aqui" : "Nenhum lançamento \(filter.rawValue.lowercased())",
                            systemImage: mode == .fixed ? "repeat" : "cart",
                            description: Text(
                                mode == .fixed
                                    ? "Toque em + e eu repito esse gasto todo mês."
                                    : "Toque em + e eu anoto a saída para você.")
                        )
                        .padding(.vertical, 24)
                    }
                    if mode == .outflows && outflowGrouping == .date {
                        ForEach(Array(dateGroups.enumerated()), id: \.element.id) { index, group in
                            CompactCardSection(
                                title: group.date.map { AppFormat.date.string(from: $0) } ?? "Sem data",
                                total: AppFormat.money(group.total, hidden: hideAmounts), items: group.items
                            ) { expenseRow($0, showCategory: true) }
                            .entrance(3 + min(index, 5))
                        }
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            CompactCardSection(
                                title: group.category, total: AppFormat.money(group.total, hidden: hideAmounts),
                                items: group.items
                            ) { expenseRow($0, showCategory: false) }
                            .entrance(3 + min(index, 5))
                        }
                    }
                }.padding(16)
            }
        } else {
            VStack(spacing: 0) {
                header(month)
                ViewThatFits(in: .horizontal) {
                    expenseSummary
                    ScrollView(.horizontal) { expenseSummary.fixedSize(horizontal: true, vertical: false) }
                }.padding(.horizontal, 24).padding(.bottom, 12)
                List {
                    if mode == .outflows && outflowGrouping == .date {
                        ForEach(dateGroups) { group in
                            Section {
                                ForEach(group.items) { expenseRow($0, showCategory: true) }
                            } header: {
                                HStack {
                                    Text(group.date.map { AppFormat.date.string(from: $0) } ?? "Sem data"); Spacer()
                                    Text(AppFormat.money(group.total, hidden: hideAmounts)).monospacedDigit()
                                }
                            }
                        }
                    } else {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.items) { expenseRow($0, showCategory: false) }
                            } header: {
                                HStack {
                                    Text(group.category); Spacer()
                                    Text(AppFormat.money(group.total, hidden: hideAmounts)).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func header(_ month: BudgetMonth) -> some View {
        ScreenHeader(
            mode == .fixed ? "Gastos fixos" : "Saídas",
            subtitle: mode == .fixed ? "Suas contas de todo mês, por categoria" : "O que saiu da conta este mês"
        ) {
            Picker("Filtro", selection: $filter) { ForEach(ExpenseFilter.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).pointerCursor().frame(width: mode == .fixed ? 430 : 330)
            if mode == .outflows {
                Picker("Visualizar por", selection: $outflowGrouping) {
                    ForEach(OutflowGrouping.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().pointerCursor().frame(width: 125).help(
                    "Visualizar saídas por data ou categoria")
            }
            if mode == .fixed {
                Button {
                    newRecurring()
                } label: {
                    Label("Novo gasto fixo", systemImage: "plus")
                }
            } else {
                Button {
                    newOutflow(month)
                } label: {
                    Label("Nova saída", systemImage: "plus")
                }
            }
        }
    }

    private func newRecurring() {
        editingRecurring = RecurringExpense(
            id: 0, description: "", category: "Outros", amount: 0, dueDay: nil, paymentMethod: .pix, notes: "",
            active: true)
    }
    private func newOutflow(_ month: BudgetMonth) {
        editing = Expense(
            id: 0, monthID: month.id, recurringID: nil, date: .now, description: "", category: "Outros", amount: 0,
            paymentMethod: .pix, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "",
            isRecurring: false)
    }

    // MARK: iPhone

    private func mobileHeader(_ month: BudgetMonth) -> some View {
        MobileHeader(
            title: mode == .fixed ? "Gastos fixos" : "Saídas",
            subtitle: mode == .fixed ? "Suas contas de todo mês" : "O que saiu da conta este mês"
        ) {
            if mode == .fixed {
                CircleActionButton(
                    title: "Sincronizar recorrentes", systemImage: "arrow.triangle.2.circlepath", prominent: false
                ) { store.syncRecurring() }
                CircleActionButton(title: "Novo gasto fixo", systemImage: "plus") { newRecurring() }
            } else {
                Menu {
                    Picker("Agrupar por", selection: $outflowGrouping) {
                        ForEach(OutflowGrouping.allCases) {
                            Label($0.rawValue, systemImage: $0 == .date ? "calendar" : "square.grid.2x2").tag($0)
                        }
                    }
                } label: {
                    CircleActionLabel(
                        systemImage: outflowGrouping == .date ? "calendar" : "square.grid.2x2", prominent: false)
                }
                .accessibilityLabel("Agrupar por \(outflowGrouping.rawValue.lowercased())")
                CircleActionButton(title: "Nova saída", systemImage: "plus") { newOutflow(month) }
            }
        }
    }

    private func total(_ statuses: Set<ExpenseStatus>) -> Double {
        modeExpenses.filter { statuses.contains($0.status) }.reduce(0) { $0 + $1.amount }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(totalTitle).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(AppBrand.mint)
                AnimatedMoney(value: filtered.reduce(0) { $0 + $1.amount }, hidden: hideAmounts)
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 8) {
                statPill("Pago", total([.paid, .prepaid]), active: filter == .paid)
                statPill("Pendente", total([.pending]), active: filter == .pending)
                Button {
                    showingInvoice = true
                } label: {
                    statPill(
                        "Na fatura", total([.invoice]), chevron: store.totals.invoice > 0, active: filter == .invoice)
                }
                .buttonStyle(.plain)
                .disabled(store.totals.invoice == 0)
                .accessibilityHint("Abre o pagamento da fatura do cartão")
            }
        }
        .animation(.snappy(duration: 0.25), value: filter)
        .foregroundStyle(.white)
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroBackground() }
    }

    /// The headline follows the status filter; the pills always break down the whole month.
    private var totalTitle: String {
        switch filter {
        case .all: mode == .fixed ? "TOTAL FIXO DO MÊS" : "TOTAL DE SAÍDAS"
        case .invoice: "NA FATURA"
        case .pending: "PENDENTE"
        case .paid: "PAGO"
        }
    }

    private func statPill(_ title: String, _ value: Double, chevron: Bool = false, active: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(title)
                if chevron { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)) }
            }
            .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            AnimatedMoney(value: value, hidden: hideAmounts).font(.footnote.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(active ? 0.22 : 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
                AppBrand.mint.opacity(active ? 0.6 : 0), lineWidth: 1))
    }

    @ViewBuilder private var summaryLabels: some View {
        Label(
            mode == .fixed
                ? "Total fixo: \(AppFormat.money(modeExpenses.reduce(0) { $0 + $1.amount }, hidden: hideAmounts))"
                : "Total de saídas: \(AppFormat.money(modeExpenses.reduce(0) { $0 + $1.amount }, hidden: hideAmounts))",
            systemImage: "sum")
        Label("Fatura atual: \(AppFormat.money(store.totals.invoice, hidden: hideAmounts))", systemImage: "creditcard")
        Label(
            "Pago antecipadamente: \(AppFormat.money(modeExpenses.filter { $0.status == .prepaid }.reduce(0) { $0 + $1.amount }, hidden: hideAmounts))",
            systemImage: "checkmark.circle")
    }

    private var expenseSummary: some View {
        HStack(spacing: 16) {
            summaryLabels
            Spacer()
            Button("Antecipar pagamento") { showingPrepayment = true }.pointerCursor().disabled(
                store.totals.invoice == 0)
            Button("Marcar fatura como paga") { confirmInvoice = true }.pointerCursor().disabled(
                store.totals.invoice == 0)
            if mode == .fixed {
                Button("Sincronizar recorrentes") { store.syncRecurring() }.pointerCursor().help(
                    "Inclui recorrências ativas que ainda não existem neste mês")
            }
        }.font(.caption).padding(16).brandSurface(cornerRadius: 14)
    }
    @ViewBuilder private func expenseRow(_ item: Expense, showCategory: Bool) -> some View {
        if compact { mobileRow(item) } else { desktopRow(item, showCategory: showCategory) }
    }

    /// iPhone: name, payment method, amount and status. Tapping opens the editor, which has every action.
    private func mobileRow(_ item: Expense) -> some View {
        Button {
            editing = item
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.description).fontWeight(.medium).lineLimit(1)
                    Text("\(item.paymentMethod.rawValue)\(dueDay(item))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(AppFormat.money(item.amount, hidden: hideAmounts)).fontWeight(.medium).monospacedDigit()
                    StatusBadge(item.status.rawValue, positive: [.paid, .prepaid].contains(item.status))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.snappy, value: item.status)
    }

    private func desktopRow(_ item: Expense, showCategory: Bool) -> some View {
        HStack {
            if !compact { BrandIcon(symbol: item.isRecurring ? "repeat" : "cart", color: AppBrand.amber) }
            VStack(alignment: .leading) {
                Text(item.description).fontWeight(.medium)
                Text(
                    "\(showCategory ? item.category + " • " : "")\(item.paymentMethod.rawValue)\(dueDay(item))\(competence(item))\(item.includedInInitialBalance ? " • já incluído no saldo inicial" : "")"
                ).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            AdaptiveStack(vertical: compact, spacing: compact ? 4 : 8) {
                Text(AppFormat.money(item.amount, hidden: hideAmounts)).monospacedDigit()
                StatusBadge(item.status.rawValue, positive: [.paid, .prepaid].contains(item.status))
            }
            CompactActionMenu {
                ForEach(ExpenseStatus.allCases) { status in
                    CompactMenuItem(status.rawValue) {
                        var copy = item; copy.status = status; store.save(copy)
                    }
                }
                if [.paid, .prepaid].contains(item.status) && !item.includedInInitialBalance {
                    CompactMenuItem("Já estava no saldo inicial") {
                        var copy = item; copy.includedInInitialBalance = true; store.save(copy)
                    }
                }
                Divider(); CompactMenuItem(item.isRecurring ? "Editar somente neste mês" : "Editar") { editing = item }
                CompactMenuItem(item.isRecurring ? "Excluir somente deste mês" : "Excluir", role: .destructive) {
                    store.delete(item)
                }
            }
        }.padding(.vertical, compact ? 6 : 10).contentShape(Rectangle()).onTapGesture { editing = item }
    }
    private func competence(_ item: Expense) -> String {
        guard let y = item.competenceYear, let m = item.competenceMonth else { return "" }
        return " • competência \(String(format: "%02d", m))/\(y)"
    }
    private func dueDay(_ item: Expense) -> String {
        guard mode == .fixed, let month = store.selectedMonth, let recurringID = item.recurringID,
            let date = store.recurring.first(where: { $0.id == recurringID })?.dueDate(in: month)
        else { return "" }
        return " • vence \(AppFormat.dayMonth.string(from: date))"
    }
}

/// iPhone: the card bill, reached from the "Na fatura" figure. Settles it in full or prepays part of it.
private struct InvoiceSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var amount: Double = 0
    @State private var confirmSettle = false

    var body: some View {
        let open = store.totals.invoice
        let prepaid = store.invoicePrepaidAmount()
        BrandForm {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Em aberto").font(.subheadline).foregroundStyle(.secondary)
                    Text(AppFormat.money(open, hidden: hideAmounts)).font(
                        .system(size: 32, weight: .medium, design: .rounded)
                    ).monospacedDigit()
                    Text(
                        prepaid > 0
                            ? "\(AppFormat.money(prepaid, hidden: hideAmounts)) já antecipados • inclui saídas e gastos fixos"
                            : "Inclui saídas e gastos fixos no cartão"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button("Quitar fatura inteira") { confirmSettle = true }
                    .fontWeight(.semibold)
                    .disabled(open == 0)
            }
            Section("Antecipar parte") {
                DecimalField("Valor", value: $amount)
                Button("Antecipar") {
                    store.prepayInvoice(amount: amount)
                    dismiss()
                }
                .disabled(amount <= 0 || amount > open + 0.005)
            }
        }
        .confirmationDialog("Quitar a fatura?", isPresented: $confirmSettle, titleVisibility: .visible) {
            Button("Marcar lançamentos como pagos") {
                store.payInvoice(); dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Todos os gastos em “Na fatura” passarão para “Pago”. Nenhuma nova despesa será criada.")
        }
        .editorSheet("Fatura do cartão", width: 380)
    }
}

private struct InvoicePrepaymentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double
    let maximum: Double
    let onConfirm: (Double) -> Void

    init(maximum: Double, initialAmount: Double, onConfirm: @escaping (Double) -> Void) {
        self.maximum = maximum
        self.onConfirm = onConfirm
        _amount = State(initialValue: initialAmount)
    }

    var body: some View {
        BrandForm {
            Text("Você pode antecipar toda a fatura ou apenas uma parte.").foregroundStyle(.secondary)
            DecimalField("Valor da antecipação", value: $amount)
            LabeledContent("Restante da fatura", value: AppFormat.money(maximum))
            #if os(macOS)
                HStack {
                    Spacer()
                    Button("Cancelar", role: .cancel) { dismiss() }.buttonStyle(.bordered).pointerCursor()
                    Button("Antecipar", action: confirm).buttonStyle(.borderedProminent).pointerCursor().disabled(
                        !canConfirm)
                }
            #endif
        }
        .editorSheet("Antecipar fatura", width: 380, saveTitle: "Antecipar", saveEnabled: canConfirm, save: confirm)
    }

    private var canConfirm: Bool { amount > 0 && amount <= maximum + 0.005 }
    private func confirm() {
        onConfirm(amount)
        dismiss()
    }
}

struct ExpenseEditor: View {
    @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss
    @Environment(\.compactLayout) private var compact
    @State var item: Expense; @State private var hasCompetence: Bool
    @State private var confirmDelete = false
    private let categories = ExpenseCategories.all
    init(item: Expense) {
        _item = State(initialValue: item); _hasCompetence = State(initialValue: item.competenceMonth != nil)
    }
    var body: some View {
        BrandForm {
            TextField("Descrição", text: $item.description)
            DecimalField("Valor", value: $item.amount)
            Picker("Categoria", selection: $item.category) { ForEach(categories, id: \.self) { Text($0) } }
            Picker("Pagamento", selection: $item.paymentMethod) {
                ForEach(PaymentMethod.allCases) { Text($0.rawValue).tag($0) }
            }
            if item.id == 0 && !item.isRecurring {
                LabeledContent("Status automático") {
                    Text(item.paymentMethod == .card ? ExpenseStatus.invoice.rawValue : ExpenseStatus.paid.rawValue)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Status", selection: $item.status) {
                    ForEach(ExpenseStatus.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Toggle("Informar data", isOn: Binding(get: { item.date != nil }, set: { item.date = $0 ? .now : nil }))
            if item.date != nil {
                DatePicker(
                    "Data", selection: Binding(get: { item.date ?? .now }, set: { item.date = $0 }),
                    displayedComponents: .date)
            }
            Toggle("Informar competência", isOn: $hasCompetence)
            if hasCompetence {
                AdaptiveStack(vertical: compact) {
                    OptionalIntField("Mês", value: $item.competenceMonth)
                    OptionalIntField("Ano", value: $item.competenceYear)
                }
            }
            Toggle("Já estava incluído no saldo inicial", isOn: $item.includedInInitialBalance)
            Text(
                "Ative para pagamentos anteriores ao saldo informado. O lançamento mantém o status, mas não será descontado novamente."
            ).font(.caption).foregroundStyle(.secondary)
            if item.isRecurring {
                Text(
                    "Valor, status e demais alterações valem somente para este mês. A recorrência dos próximos meses permanece inalterada."
                ).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Observação", text: $item.notes, axis: .vertical).lineLimit(2...4)
            #if os(iOS)
                if item.id != 0 {
                    Button(deleteTitle, role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                }
            #endif
            EditorButtons(saveEnabled: canSave, save: save)
        }
        .confirmationDialog(deleteTitle + "?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(deleteTitle, role: .destructive) {
                store.delete(item); dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(item.isRecurring ? "O gasto fixo continua nos próximos meses." : "Esta ação não pode ser desfeita.")
        }
        .editorSheet(item.id == 0 ? "Nova saída" : "Editar lançamento", width: 450, saveEnabled: canSave, save: save)
    }
    private var deleteTitle: String { item.isRecurring ? "Excluir somente deste mês" : "Excluir lançamento" }
    private var canSave: Bool { !item.description.isEmpty && item.amount >= 0 }
    private func save() {
        if !hasCompetence { item.competenceMonth = nil; item.competenceYear = nil }; store.save(item); dismiss()
    }
}
