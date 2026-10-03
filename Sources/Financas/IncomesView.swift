import SwiftUI

struct IncomesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    @State private var editing: Income?
    var extrasOnly = false

    var body: some View {
        if let month = store.selectedMonth {
            Group {
                if compact {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            MobileHeader(
                                title: extrasOnly ? "Entradas extras" : "Entradas",
                                subtitle: "O que entrou e o que ainda vem"
                            ) {
                                CircleActionButton(title: "Nova entrada", systemImage: "plus") { newIncome(month) }
                            }
                            .entrance(0)
                            totalCard.entrance(1)
                            if !extrasOnly {
                                CompactCardSection(title: "Entradas fixas", items: store.incomes.filter(\.isFixed)) {
                                    row($0)
                                }.entrance(2)
                            }
                            CompactCardSection(title: "Entradas extras", items: store.incomes.filter { !$0.isFixed }) {
                                row($0)
                            }.entrance(3)
                        }.padding(16)
                    }
                } else {
                    VStack(spacing: 0) {
                        header(month)
                        List {
                            if !extrasOnly {
                                Section("Entradas fixas") { ForEach(store.incomes.filter(\.isFixed)) { row($0) } }
                            }
                            Section("Entradas extras") { ForEach(store.incomes.filter { !$0.isFixed }) { row($0) } }
                        }
                    }
                }
            }
            .sheet(item: $editing) { IncomeEditor(item: $0) }
        } else {
            EmptyMonthView()
        }
    }

    private func header(_ month: BudgetMonth) -> some View {
        ScreenHeader(
            extrasOnly ? "Entradas extras" : "Entradas",
            subtitle: extrasOnly ? "Bônus, freelas e reembolsos que chegaram" : "O que entrou e o que ainda vem"
        ) {
            Button {
                newIncome(month)
            } label: {
                Label("Nova entrada", systemImage: "plus")
            }
        }
    }

    private func newIncome(_ month: BudgetMonth) {
        editing = Income(
            id: 0, monthID: month.id, date: .now, description: "", category: "Outros", amount: 0, expectedDay: nil,
            status: .pending, isFixed: false)
    }

    private var totalCard: some View {
        let received = store.incomes.filter { $0.status == .received }.reduce(0) { $0 + $1.amount }
        let pending = store.incomes.filter { $0.status == .pending }.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TOTAL DO MÊS").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(AppBrand.mint)
                AnimatedMoney(value: received + pending, hidden: hideAmounts)
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 8) {
                ForEach([("Recebido", received), ("A receber", pending)], id: \.0) { title, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                        AnimatedMoney(value: value, hidden: hideAmounts).font(.footnote.weight(.semibold))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroBackground() }
    }

    @ViewBuilder private func row(_ item: Income) -> some View {
        if compact { mobileRow(item) } else { desktopRow(item) }
    }

    /// iPhone: name, expected day or date, amount and status. Tapping opens the editor, which has every action.
    private func mobileRow(_ item: Income) -> some View {
        Button {
            editing = item
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.description).fontWeight(.medium).lineLimit(1)
                    Text(
                        item.isFixed
                            ? "Dia \(item.expectedDay.map(String.init) ?? "—")"
                            : item.date.map(AppFormat.date.string) ?? "Sem data"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(AppFormat.money(item.amount, hidden: hideAmounts)).fontWeight(.medium).monospacedDigit()
                    StatusBadge(item.status.rawValue, positive: item.status == .received)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.snappy, value: item.status)
    }

    private func desktopRow(_ item: Income) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            if !compact { BrandIcon(symbol: item.isFixed ? "calendar" : "arrow.down.left") }
            VStack(alignment: .leading) {
                Text(item.description).fontWeight(.medium)
                Text(
                    item.isFixed
                        ? "Previsto dia \(item.expectedDay.map(String.init) ?? "—")"
                        : "\(item.category) • \(item.date.map(AppFormat.date.string) ?? "Sem data")"
                ).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            AdaptiveStack(vertical: compact, spacing: compact ? 4 : 14) {
                Text(AppFormat.money(item.amount, hidden: hideAmounts)).monospacedDigit()
                StatusBadge(item.status.rawValue, positive: item.status == .received)
            }
            CompactActionMenu {
                if item.status != .received {
                    CompactMenuItem("Marcar como recebido") {
                        var copy = item; copy.status = .received; if copy.date == nil { copy.date = .now };
                        store.save(copy)
                    }
                }; CompactMenuItem("Editar") { editing = item };
                CompactMenuItem("Excluir", role: .destructive) { store.delete(item) }
            }
        }.padding(.vertical, compact ? 6 : 10).contentShape(Rectangle()).onTapGesture { editing = item }
    }
}

struct IncomeEditor: View {
    @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss
    @State var item: Income
    @State private var confirmDelete = false
    private let categories = ["PLR", "Bônus", "Freela", "Presente", "Reembolso", "Venda", "Outros"]

    var body: some View {
        BrandForm {
            Toggle("Entrada fixa", isOn: $item.isFixed)
            TextField("Descrição", text: $item.description)
            DecimalField("Valor", value: $item.amount)
            if item.isFixed {
                OptionalIntField("Dia esperado", value: $item.expectedDay)
            } else {
                DatePicker(
                    "Data", selection: Binding(get: { item.date ?? .now }, set: { item.date = $0 }),
                    displayedComponents: .date)
                Picker("Categoria", selection: $item.category) { ForEach(categories, id: \.self) { Text($0) } }
            }
            Picker("Status", selection: $item.status) { ForEach(IncomeStatus.allCases) { Text($0.rawValue).tag($0) } }
            #if os(iOS)
                if item.id != 0 {
                    Button("Excluir entrada", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                }
            #endif
            EditorButtons(saveEnabled: canSave, save: save)
        }
        .confirmationDialog("Excluir entrada?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir entrada", role: .destructive) {
                store.delete(item); dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação não pode ser desfeita.")
        }
        .editorSheet(item.id == 0 ? "Nova entrada" : "Editar entrada", width: 420, saveEnabled: canSave, save: save)
    }
    private var canSave: Bool { !item.description.isEmpty && item.amount >= 0 }
    private func save() {
        // Like the old "Marcar como recebido" action: a fixed income received without a date gets today.
        if item.status == .received && item.date == nil { item.date = .now }
        store.save(item); dismiss()
    }
}

struct ScreenHeader<Actions: View>: View {
    @Environment(\.compactLayout) private var compact
    let title: String; let subtitle: String; @ViewBuilder let actions: Actions
    let inset: CGFloat
    init(_ title: String, subtitle: String, inset: CGFloat = 24, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.subtitle = subtitle; self.inset = inset; self.actions = actions()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: compact ? 28 : 34, weight: .medium, design: .serif))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            BrandGlassControls {
                if compact {
                    VStack(alignment: .leading, spacing: 10) { actions }.brandAction(prominent: true)
                } else {
                    HStack(spacing: 12) { actions }.controlSize(.large).brandAction(prominent: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(inset)
    }
}

struct EditorButtons: View {
    @Environment(\.dismiss) private var dismiss
    let saveEnabled: Bool; let save: () -> Void
    /// On iOS the actions live in the sheet's navigation bar (see `editorSheet`).
    var body: some View {
        #if os(macOS)
            BrandGlassControls(spacing: 0) {
                HStack(spacing: 16) {
                    Spacer()
                    Button("Cancelar") { dismiss() }.brandAction()
                    Button("Salvar", action: save).keyboardShortcut(.defaultAction).disabled(!saveEnabled).brandAction(
                        prominent: true)
                }
            }.padding(.top, 8)
        #endif
    }
}

struct StatusBadge: View {
    @Environment(\.compactLayout) private var compact
    let text: String; let positive: Bool
    init(_ text: String, positive: Bool = false) { self.text = text; self.positive = positive }
    var body: some View {
        Text(text).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5).background(
            (positive ? AppBrand.accent : AppBrand.amber).opacity(0.12), in: Capsule()
        ).foregroundStyle(positive ? AppBrand.accent : AppBrand.amber).lineLimit(compact ? 1 : nil).fixedSize(
            horizontal: compact, vertical: false
        ).frame(width: compact ? nil : 110).pointerCursor()
    }
}
