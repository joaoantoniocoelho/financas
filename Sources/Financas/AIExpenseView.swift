import SwiftUI

struct AIExpenseView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @AppStorage("ollamaBaseURL") private var baseURL = "http://192.168.0.250:11434"
    @AppStorage("ollamaModel") private var model = "qwen3.5:9b"
    let month: BudgetMonth
    @State private var text = ""
    @State private var drafts: [Draft] = []
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var saving = false
    @State private var error: String?
    @State private var mode: Mode = .menu

    private enum Mode { case menu, capture, review }

    struct Draft: Identifiable {
        let id = UUID()
        var description: String
        var amount: String
        var category: String
        var payment: String
        var date: Date?
        var includedInInitialBalance = false

        var decimal: Decimal? {
            guard amount.range(of: #"^\d+(?:,\d{1,2})?$"#, options: .regularExpression) != nil,
                  let value = Decimal(string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
                  value > 0, value <= 999_999_999 else { return nil }
            return value
        }
        var valid: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && decimal != nil && PaymentMethod(rawValue: payment) != nil && date != nil }
        func expense(monthID: Int64) -> Expense {
            Expense(id: 0, monthID: monthID, recurringID: nil, date: date, description: description.trimmingCharacters(in: .whitespacesAndNewlines), category: category, amount: NSDecimalNumber(decimal: decimal!).doubleValue, paymentMethod: PaymentMethod(rawValue: payment)!, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false, includedInInitialBalance: includedInInitialBalance)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Assistente Finanças", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button { task?.cancel(); isPresented = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            Text("Mês: \(month.title)").font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    assistantBubble("O que você quer fazer?")
                    if mode == .menu {
                        Button { mode = .capture } label: {
                            Label("Registrar saída", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderedProminent)
                    } else {
                        assistantBubble(mode == .capture ? "Descreva os gastos realizados. Você pode escrever vários de uma vez." : "Revise os lançamentos encontrados antes de salvar.")
                        if mode == .capture {
                            TextEditor(text: $text).frame(height: 100).border(.quaternary).disabled(busy)
                            Text("Ex.: Gastei 42,90 no almoço no pix e 89 de Uber no cartão ontem.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            review
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
                }
            }.frame(maxHeight: 440)

            HStack {
                if mode != .menu { Button("Voltar") { mode = .menu; drafts = []; error = nil } }
                Spacer()
                if busy { ProgressView().controlSize(.small); Text("Interpretando…") }
                else if mode == .capture {
                    Button("Interpretar", action: extract).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000)
                } else if mode == .review {
                    Button("Confirmar e salvar", action: save).buttonStyle(.borderedProminent).disabled(saving || !drafts.allSatisfy(\.valid))
                }
            }
        }
        .padding(18).frame(width: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.1)))
        .shadow(radius: 18, y: 8)
        .onDisappear { task?.cancel() }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($drafts) { $draft in
                VStack(alignment: .leading, spacing: 7) {
                    HStack { TextField("Descrição", text: $draft.description); Button(role: .destructive) { drafts.removeAll { $0.id == draft.id } } label: { Image(systemName: "trash") } }
                    HStack { TextField("Valor", text: $draft.amount); Picker("Categoria", selection: $draft.category) { ForEach(ExpenseCategories.all, id: \.self) { Text($0).tag($0) } } }
                    Picker("Pagamento", selection: $draft.payment) { Text("Selecione…").tag(""); ForEach(PaymentMethod.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                    DatePicker("Data", selection: Binding(get: { draft.date ?? .now }, set: { draft.date = $0 }), displayedComponents: .date)
                    Toggle("Já estava no saldo inicial", isOn: $draft.includedInInitialBalance)
                    if !draft.valid { Text("Complete os campos obrigatórios.").font(.caption).foregroundStyle(.orange) }
                }.padding(10).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Total: \(AppFormat.money(NSDecimalNumber(decimal: drafts.compactMap(\.decimal).reduce(0, +)).doubleValue))").fontWeight(.semibold)
        }
    }

    private func assistantBubble(_ text: String) -> some View {
        Text(text).font(.callout).padding(10).background(AppBrand.forest.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func extract() {
        error = nil
        busy = true
        let extraction = ExpenseExtraction(text: text)
        let configuration = AIConfiguration(baseURL: baseURL, model: model)
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let output = try await AIService().run(extraction, configuration: configuration)
                try Task.checkCancellation()
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                drafts = output.expenses.map { item in
                    Draft(description: item.description,
                          amount: extraction.amounts.first { $0.id == item.amountID }?.value.replacingOccurrences(of: ".", with: ",") ?? "",
                          category: item.category, payment: item.payment,
                          date: extraction.dates.first { $0.id == item.dateID }.flatMap { formatter.date(from: $0.value) })
                }
                if drafts.isEmpty { error = "Nenhum gasto identificado. Inclua a descrição dos gastos realizados." }
                else { mode = .review }
            } catch {
                if !Task.isCancelled { self.error = "Não foi possível interpretar: \(error.localizedDescription)" }
            }
        }
    }

    private func save() {
        guard !saving, !drafts.isEmpty, drafts.allSatisfy(\.valid) else { return }
        saving = true
        do {
            try store.saveExpenseBatch(drafts.map { $0.expense(monthID: month.id) })
            isPresented = false
        } catch {
            saving = false
            self.error = "Nenhum lançamento foi salvo: \(error.localizedDescription)"
        }
    }
}
