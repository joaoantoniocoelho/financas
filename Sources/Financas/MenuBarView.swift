import AppKit
import SwiftUI

private enum MenuBarLayout {
    static let width: CGFloat = 380
    static let padding: CGFloat = 12
    static let sectionSpacing: CGFloat = 8

    static let markSize: CGFloat = 30
    static let titleSize: CGFloat = 20
    static let headerSpacing: CGFloat = 8
    static let titleStackSpacing: CGFloat = 0

    static let monthStepperHeight: CGFloat = 24
    static let monthStepperChevronSize: CGFloat = 12

    static let balancePaddingH: CGFloat = 12
    static let balancePaddingV: CGFloat = 8
    static let balanceSpacing: CGFloat = 2
    static let balanceCorner: CGFloat = 14

    static let infoRowSpacing: CGFloat = 8
    static let actionSpacing: CGFloat = 8
    static let actionMinHeight: CGFloat = 28
    static let actionCorner: CGFloat = 10

    static let footerIconSize: CGFloat = 18
    static let clickTarget: CGFloat = 24
}

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var editingExpense: Expense?
    @State private var editingIncome: Income?

    let openMainWindow: () -> Void

    var body: some View {
        overview
            .environment(\.hideAmounts, hideAmounts)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: MenuBarLayout.sectionSpacing) {
            header

            if let month = store.selectedMonth {
                monthPicker
                balanceCard(month)
                totals

                if let salary = store.nextSalary() {
                    nextSalary(salary)
                }

                Divider()
                quickActions(month)
            } else {
                ContentUnavailableView(
                    "Nenhum mês",
                    systemImage: "calendar",
                    description: Text("Crie um mês para começar a registrar suas finanças.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)

                Button("Criar primeiro mês", systemImage: "plus") {
                    store.createNextMonth()
                }
                .brandAction(prominent: true)
                .frame(maxWidth: .infinity)
            }

            Divider()
            footer
        }
        .padding(MenuBarLayout.padding)
        .frame(width: MenuBarLayout.width)
        .fixedSize(horizontal: false, vertical: true)
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
            Button("OK") { store.errorMessage = nil }.pointerCursor()
        } message: {
            Text(store.errorMessage ?? "Erro desconhecido")
        }
    }

    private var header: some View {
        HStack(spacing: MenuBarLayout.headerSpacing) {
            BrandMark().frame(width: MenuBarLayout.markSize, height: MenuBarLayout.markSize)
            VStack(alignment: .leading, spacing: MenuBarLayout.titleStackSpacing) {
                Text("Finanças").font(.system(size: MenuBarLayout.titleSize, weight: .semibold, design: .serif))
                Text("Visão rápida").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                hideAmounts.toggle()
            } label: {
                Image(systemName: hideAmounts ? "eye.slash" : "eye")
                    .frame(minWidth: MenuBarLayout.clickTarget, minHeight: MenuBarLayout.clickTarget)
            }
            .brandAction()
            .controlSize(.small)
            .help(hideAmounts ? "Mostrar valores" : "Ocultar valores")
        }
    }

    private var monthPicker: some View {
        HStack(spacing: 10) {
            monthStepButton(offset: -1, symbol: "chevron.left", help: "Mês anterior")
            Text(monthStepperLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityLabel("Mês")
                .accessibilityValue(store.selectedMonth?.title ?? "")
            monthStepButton(offset: 1, symbol: "chevron.right", help: "Próximo mês")
        }
        .frame(minHeight: MenuBarLayout.monthStepperHeight)
    }

    private var monthStepperLabel: String {
        store.selectedMonth?.title.lowercased(with: Locale(identifier: "pt_BR")) ?? ""
    }

    private func monthStepButton(offset: Int, symbol: String, help: String) -> some View {
        let enabled = adjacentMonthID(offset) != nil
        return Button {
            guard let id = adjacentMonthID(offset) else { return }
            store.select(id)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: MenuBarLayout.monthStepperChevronSize, weight: .semibold))
                .foregroundStyle(enabled ? AppBrand.accent : .secondary)
                .frame(width: MenuBarLayout.clickTarget, height: MenuBarLayout.clickTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(help)
    }

    private func adjacentMonthID(_ offset: Int) -> Int64? {
        guard let id = store.selectedMonthID,
              let index = store.months.firstIndex(where: { $0.id == id }) else { return nil }
        let next = index + offset
        guard store.months.indices.contains(next) else { return nil }
        return store.months[next].id
    }

    private func balanceCard(_ month: BudgetMonth) -> some View {
        VStack(alignment: .leading, spacing: MenuBarLayout.balanceSpacing) {
            Label("Saldo atual", systemImage: "wallet.pass")
                .font(.caption)
                .foregroundStyle(AppBrand.mint)
            Text(AppFormat.money(month.currentBalance, hidden: hideAmounts))
                .font(.title.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, MenuBarLayout.balancePaddingH)
        .padding(.vertical, MenuBarLayout.balancePaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppBrand.forest, in: RoundedRectangle(cornerRadius: MenuBarLayout.balanceCorner, style: .continuous))
    }

    private var totals: some View {
        MenuBarInfoRow(
            icon: "clock",
            title: "Pendentes",
            detail: "Pendentes: \(AppFormat.money(store.totals.pending, hidden: hideAmounts)) • Na fatura: \(AppFormat.money(store.totals.invoice, hidden: hideAmounts))",
            amount: store.totals.pending + store.totals.invoice,
            hidden: hideAmounts
        )
    }

    private func nextSalary(_ salary: NextSalary) -> some View {
        MenuBarInfoRow(
            icon: "calendar.badge.clock",
            title: "Próxima entrada fixa",
            detail: salary.days == 0 ? "Hoje" : "Em \(salary.days) \(salary.days == 1 ? "dia" : "dias")",
            amount: salary.amount,
            hidden: hideAmounts
        )
    }

    private func quickActions(_ month: BudgetMonth) -> some View {
        HStack(spacing: MenuBarLayout.actionSpacing) {
            Button {
                editingExpense = Expense(
                    id: 0, monthID: month.id, recurringID: nil, date: .now,
                    description: "", category: "Outros", amount: 0,
                    paymentMethod: .pix, status: .pending,
                    competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false
                )
            } label: {
                Label("Nova saída", systemImage: "minus.circle")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: MenuBarLayout.actionMinHeight)
            }
            .buttonStyle(.plain).pointerCursor()
            .brandSurface(cornerRadius: MenuBarLayout.actionCorner)

            Button {
                editingIncome = Income(
                    id: 0, monthID: month.id, date: .now, description: "",
                    category: "Outros", amount: 0, expectedDay: nil,
                    status: .pending, isFixed: false
                )
            } label: {
                Label("Nova entrada", systemImage: "plus.circle")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: MenuBarLayout.actionMinHeight)
            }
            .buttonStyle(.plain).pointerCursor()
            .brandSurface(cornerRadius: MenuBarLayout.actionCorner)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: openMainWindow) {
                Label {
                    Text("Abrir Finanças")
                } icon: {
                    BrandMark()
                        .frame(width: MenuBarLayout.footerIconSize, height: MenuBarLayout.footerIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: MenuBarLayout.footerIconSize * 0.28, style: .continuous))
                }
            }
            .buttonStyle(.plain).pointerCursor()
            .font(.callout)
            .frame(minHeight: MenuBarLayout.clickTarget)
            Spacer(minLength: 8)
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
                    .frame(width: MenuBarLayout.clickTarget, height: MenuBarLayout.clickTarget)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
        }
    }
}

private struct MenuBarInfoRow: View {
    let icon: String
    let title: String
    let detail: String
    let amount: Double
    let hidden: Bool

    var body: some View {
        HStack(spacing: MenuBarLayout.infoRowSpacing) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppBrand.accent)
                .frame(width: MenuBarLayout.clickTarget, height: MenuBarLayout.clickTarget)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            Text(AppFormat.money(amount, hidden: hidden))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
