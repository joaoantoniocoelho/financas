import AppKit
import Charts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var editingExpense: Expense?
    @State private var editingIncome: Income?

    let openMainWindow: () -> Void

    private struct CategorySpending: Identifiable {
        let category: String
        let total: Double
        var id: String { category }
    }

    private var spendingByCategory: [CategorySpending] {
        let expenses = store.expenses.filter {
            [.paid, .prepaid, .invoice].contains($0.status)
        }
        return Dictionary(grouping: expenses, by: \.category)
            .map { CategorySpending(category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var totalSpending: Double {
        spendingByCategory.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let month = store.selectedMonth {
                monthPicker
                balanceCard(month)
                totals
                categoryChart

                if let salary = store.nextSalary() {
                    nextSalary(salary)
                }

                Divider()
                BrandGlassControls { quickActions(month) }
            } else {
                ContentUnavailableView(
                    "Nenhum mês",
                    systemImage: "calendar",
                    description: Text("Crie um mês para começar a registrar suas finanças.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)

                Button("Criar primeiro mês", systemImage: "plus") {
                    store.createNextMonth()
                }
                .brandAction(prominent: true)
                .frame(maxWidth: .infinity)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
        .background { BrandBackground() }
        .environment(\.hideAmounts, hideAmounts)
        .sheet(item: $editingExpense) { ExpenseEditor(item: $0) }
        .sheet(item: $editingIncome) { IncomeEditor(item: $0) }
        .alert(
            "Não foi possível concluir",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Erro desconhecido")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Finanças").font(.system(size: 22, weight: .semibold, design: .serif))
                Text("Visão rápida").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                hideAmounts.toggle()
            } label: {
                Image(systemName: hideAmounts ? "eye.slash" : "eye")
            }
            .brandAction()
            .controlSize(.small)
            .help(hideAmounts ? "Mostrar valores" : "Ocultar valores")
        }
    }

    private var monthPicker: some View {
        Picker(
            "Mês",
            selection: Binding(
                get: { store.selectedMonthID ?? 0 },
                set: store.select
            )
        ) {
            ForEach(store.months) { month in
                Text(month.title).tag(month.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private func balanceCard(_ month: BudgetMonth) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Saldo atual", systemImage: "wallet.pass")
                .font(.caption)
                .foregroundStyle(AppBrand.mint)
            Text(AppFormat.money(month.currentBalance, hidden: hideAmounts))
                .font(.title.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppBrand.forest, in: RoundedRectangle(cornerRadius: 18))
    }

    private var totals: some View {
        HStack(spacing: 10) {
            MenuBarMetric(title: "Pendentes", value: store.totals.pending, icon: "clock", color: .orange, hidden: hideAmounts)
            MenuBarMetric(title: "Na fatura", value: store.totals.invoice, icon: "creditcard", color: .orange, hidden: hideAmounts)
        }
    }

    @ViewBuilder
    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Gastos por categoria", systemImage: "chart.pie")
                .font(.subheadline.weight(.semibold))

            if spendingByCategory.isEmpty {
                Text("Nenhum gasto realizado neste mês.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                HStack(spacing: 14) {
                    Chart(spendingByCategory) { item in
                        SectorMark(
                            angle: .value("Valor", item.total),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .cornerRadius(2)
                        .foregroundStyle(by: .value("Categoria", item.category))
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(
                        domain: spendingByCategory.map(\.category),
                        range: spendingByCategory.indices.map(chartColor)
                    )
                    .chartBackground { _ in
                        VStack(spacing: 1) {
                            Text("Total")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(AppFormat.money(totalSpending, hidden: hideAmounts))
                                .font(.caption.weight(.semibold))
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                        }
                        .frame(width: 76)
                    }
                    .frame(width: 145, height: 145)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(spendingByCategory.prefix(4).enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(chartColor(index))
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.category)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(AppFormat.money(item.total, hidden: hideAmounts))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }

                        if spendingByCategory.count > 4 {
                            Text("+ \(spendingByCategory.count - 4) categorias")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .brandSurface(cornerRadius: 16)
    }

    private func chartColor(_ index: Int) -> Color {
        AppBrand.chartColors[index % AppBrand.chartColors.count]
    }

    private func nextSalary(_ salary: NextSalary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(AppBrand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Próxima entrada fixa").font(.caption).foregroundStyle(.secondary)
                Text(salary.days == 0 ? "Hoje" : "Em \(salary.days) \(salary.days == 1 ? "dia" : "dias")")
                    .fontWeight(.semibold)
            }
            Spacer()
            Text(AppFormat.money(salary.amount, hidden: hideAmounts))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func quickActions(_ month: BudgetMonth) -> some View {
        HStack(spacing: 10) {
            Button {
                editingExpense = Expense(
                    id: 0, monthID: month.id, recurringID: nil, date: .now,
                    description: "", category: "Outros", amount: 0,
                    paymentMethod: .pix, status: .pending,
                    competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false
                )
            } label: {
                Label("Nova saída", systemImage: "minus.circle").frame(maxWidth: .infinity)
            }
            .brandAction(prominent: true)

            Button {
                editingIncome = Income(
                    id: 0, monthID: month.id, date: .now, description: "",
                    category: "Outros", amount: 0, expectedDay: nil,
                    status: .pending, isFixed: false
                )
            } label: {
                Label("Nova entrada", systemImage: "plus.circle").frame(maxWidth: .infinity)
            }
            .brandAction()
        }
    }

    private var footer: some View {
        HStack {
            Button("Abrir Finanças", systemImage: "macwindow", action: openMainWindow)
                .buttonStyle(.plain)
            Spacer()
            Menu {
                Button("Novo mês", systemImage: "calendar.badge.plus") {
                    store.createNextMonth()
                }
                Divider()
                Button("Encerrar Finanças", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct MenuBarMetric: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color
    let hidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(AppFormat.money(value, hidden: hidden))
                .font(.headline)
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandSurface(cornerRadius: 14)
    }
}
