import SwiftUI

struct IncomesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var editing: Income?
    var extrasOnly = false

    var body: some View {
        if let month = store.selectedMonth {
            VStack(spacing: 0) {
                ScreenHeader(extrasOnly ? "Entradas extras" : "Entradas", subtitle: extrasOnly ? "Bônus, freelas, reembolsos e outras rendas" : "Fixas e extras recebidas no mês") {
                    Button { editing = Income(id: 0, monthID: month.id, date: .now, description: "", category: "Outros", amount: 0, expectedDay: nil, status: .pending, isFixed: false) } label: { Label("Nova entrada", systemImage: "plus") }
                }
                List {
                    if !extrasOnly { Section("Entradas fixas") { ForEach(store.incomes.filter(\.isFixed)) { row($0) } } }
                    Section("Entradas extras") { ForEach(store.incomes.filter { !$0.isFixed }) { row($0) } }
                }
            }
            .sheet(item: $editing) { IncomeEditor(item: $0) }
        } else { EmptyMonthView() }
    }

    private func row(_ item: Income) -> some View {
        HStack(spacing: 14) {
            BrandIcon(symbol: item.isFixed ? "calendar" : "arrow.down.left")
            VStack(alignment: .leading) {
                Text(item.description).fontWeight(.medium)
                Text(item.isFixed ? "Previsto dia \(item.expectedDay.map(String.init) ?? "—")" : "\(item.category) • \(item.date.map(AppFormat.date.string) ?? "Sem data")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(AppFormat.money(item.amount, hidden: hideAmounts)).monospacedDigit()
            StatusBadge(item.status.rawValue, positive: item.status == .received)
            CompactActionMenu { if item.status != .received { CompactMenuItem("Marcar como recebido") { var copy=item;copy.status = .received;if copy.date == nil { copy.date = .now };store.save(copy) } }; CompactMenuItem("Editar") { editing=item }; CompactMenuItem("Excluir", role:.destructive) { store.delete(item) } }
        }.padding(.vertical, 10).contentShape(Rectangle()).onTapGesture { editing=item }
    }
}

struct IncomeEditor: View {
    @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss
    @State var item: Income
    private let categories = ["PLR","Bônus","Freela","Presente","Reembolso","Venda","Outros"]

    var body: some View {
        Form {
            Toggle("Entrada fixa", isOn: $item.isFixed)
            TextField("Descrição", text: $item.description)
            TextField("Valor", value: $item.amount, format: .number)
            if item.isFixed { TextField("Dia esperado", value: $item.expectedDay, format: .number) }
            else {
                DatePicker("Data", selection: Binding(get:{item.date ?? .now},set:{item.date=$0}), displayedComponents:.date)
                Picker("Categoria", selection:$item.category) { ForEach(categories,id:\.self){Text($0)} }
            }
            Picker("Status", selection:$item.status) { ForEach(IncomeStatus.allCases){Text($0.rawValue).tag($0)} }
            EditorButtons(saveEnabled: !item.description.isEmpty && item.amount >= 0) { store.save(item); dismiss() }
        }.padding().frame(width:420).navigationTitle(item.id == 0 ? "Nova entrada" : "Editar entrada")
    }
}

struct ScreenHeader<Actions: View>: View {
    let title:String; let subtitle:String; @ViewBuilder let actions:Actions
    let inset: CGFloat
    init(_ title:String,subtitle:String,inset:CGFloat=24,@ViewBuilder actions:()->Actions){self.title=title;self.subtitle=subtitle;self.inset=inset;self.actions=actions()}
    var body:some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 34, weight: .medium, design: .serif))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            BrandGlassControls {
                HStack(spacing: 12) { actions }.controlSize(.large).brandAction(prominent: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(inset)
    }
}

struct EditorButtons: View {
    @Environment(\.dismiss) private var dismiss
    let saveEnabled:Bool; let save:()->Void
    var body:some View {
        BrandGlassControls(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()
                Button("Cancelar") { dismiss() }.brandAction()
                Button("Salvar", action: save).keyboardShortcut(.defaultAction).disabled(!saveEnabled).brandAction(prominent: true)
            }
        }.padding(.top, 8)
    }
}

struct StatusBadge: View {
    let text:String; let positive:Bool
    init(_ text:String,positive:Bool=false){self.text=text;self.positive=positive}
    var body:some View { Text(text).font(.caption.weight(.medium)).padding(.horizontal,10).padding(.vertical,5).background((positive ? AppBrand.accent : AppBrand.amber).opacity(0.12),in:Capsule()).foregroundStyle(positive ? AppBrand.accent : AppBrand.amber).frame(width:110).pointerCursor() }
}
