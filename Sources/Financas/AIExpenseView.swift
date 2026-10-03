import SwiftUI

struct AIExpenseView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @AppStorage("ollamaBaseURL") private var baseURL = "http://192.168.0.250:11434"
    @AppStorage("ollamaModel") private var model = "qwen3.5:9b"
    let month: BudgetMonth
    var panelWidth: CGFloat = 430
    var returnsToOverview = false
    @State private var text = ""
    @State private var drafts: [Draft] = []
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var saving = false
    @State private var mode: Mode = .menu
    @State private var messages = [Message(text: "Olá! Posso ajudar você a registrar seus gastos. O que vamos fazer?")]
    @State private var destination: BudgetMonth?
    @FocusState private var composerFocused: Bool

    private enum Mode: Equatable { case menu, capture, missing(Int, Field), review, completed }
    private enum Field { case description, amount, payment, date }
    private struct Message: Identifiable {
        let id = UUID()
        let text: String
        var fromUser = false
    }

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
                let value = Decimal(
                    string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
                value > 0, value <= 999_999_999
            else { return nil }
            return value
        }
        var valid: Bool {
            !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && decimal != nil
                && PaymentMethod(rawValue: payment) != nil && date != nil
        }
        func expense(monthID: Int64) -> Expense {
            Expense(
                id: 0, monthID: monthID, recurringID: nil, date: date,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines), category: category,
                amount: NSDecimalNumber(decimal: decimal!).doubleValue,
                paymentMethod: PaymentMethod(rawValue: payment)!, status: .pending, competenceYear: nil,
                competenceMonth: nil, notes: "", isRecurring: false, includedInInitialBalance: includedInInitialBalance)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(AppBrand.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Assistente Finanças").font(.headline)
                    Text((destination ?? month).title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    task?.cancel(); isPresented = false
                } label: {
                    Image(systemName: returnsToOverview ? "arrow.uturn.backward" : "xmark").frame(width: 28, height: 28)
                }.buttonStyle(.plain).pointerCursor()
                    .help(returnsToOverview ? "Voltar à visão rápida" : "Fechar conversa")
                    .accessibilityLabel(returnsToOverview ? "Voltar à visão rápida" : "Fechar conversa")
            }.padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { message in
                            HStack {
                                if message.fromUser { Spacer(minLength: 35) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.fromUser ? "Você" : "Assistente").font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(message.text).font(.callout).textSelection(.enabled)
                                }
                                .padding(12)
                                .background(
                                    message.fromUser ? AppBrand.accent.opacity(0.18) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 14))
                                if !message.fromUser { Spacer(minLength: 25) }
                            }
                        }
                        if busy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small);
                                Text("Estou organizando seus gastos…").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            actions
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("latest", anchor: .bottom) } }
                .onChange(of: busy) { _, _ in withAnimation { proxy.scrollTo("latest", anchor: .bottom) } }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(
                        acceptsText ? "Digite sua mensagem…" : "Escolha uma opção acima", text: $text, axis: .vertical
                    )
                    .lineLimit(1...4).textFieldStyle(.plain).focused($composerFocused)
                    .disabled(!acceptsText || busy).onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)).foregroundStyle(
                            AppBrand.accent)
                    }.buttonStyle(.plain).pointerCursor().disabled(!canSend).help("Enviar mensagem")
                }
                if text.count > 4000 {
                    Text("Use até 4.000 caracteres por mensagem.").font(.caption).foregroundStyle(.red)
                }
            }.padding(14)
        }
        #if os(macOS)
            .frame(width: panelWidth, height: 540)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.1)))
            .shadow(radius: 18, y: 8)
        #else
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { BrandBackground() }
        #endif
        .onDisappear { task?.cancel() }
    }

    private var acceptsText: Bool {
        switch mode {
        case .capture, .missing: return true;
        default: return false
        }
    }
    private var canSend: Bool {
        acceptsText && !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 4000
    }

    @ViewBuilder private var actions: some View {
        switch mode {
        case .menu, .completed:
            Button("Registrar saída", systemImage: "arrow.up.circle") {
                destination = month
                drafts = []; saving = false; text = ""; mode = .capture
                append("Registrar saída", user: true)
                append(
                    "Me conte o que você gastou. Inclua valor, pagamento e data. Pode enviar vários gastos juntos.\n\nPor exemplo: Gastei 42,90 no almoço no pix e 89 de Uber no cartão ontem."
                )
                composerFocused = true
            }
            .buttonStyle(.bordered).pointerCursor()
        case .review:
            VStack(alignment: .leading, spacing: 10) {
                ForEach($drafts) { $draft in
                    Toggle("\(draft.description): já incluído no saldo inicial", isOn: $draft.includedInInitialBalance)
                        .font(.caption)
                }
                HStack {
                    Button("Confirmar e salvar", action: save).buttonStyle(.borderedProminent).pointerCursor().disabled(
                        saving || drafts.isEmpty || !drafts.allSatisfy(\.valid))
                    Button("Corrigir") {
                        append("Quero corrigir os gastos.", user: true)
                        append(
                            "Envie novamente a lista completa com as correções. Vou substituir a proposta e pedir sua confirmação antes de salvar."
                        )
                        drafts = []; mode = .capture; composerFocused = true
                    }
                }
                Button("Cancelar lançamento", action: cancel).pointerCursor()
            }
        case .missing(_, .payment):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(PaymentMethod.allCases) { method in
                    Button(method.rawValue) {
                        text = method.rawValue; send()
                    }.buttonStyle(.bordered).pointerCursor()
                }
                Button("Cancelar lançamento", action: cancel).pointerCursor()
            }
        case .capture, .missing:
            Button("Cancelar lançamento", action: cancel).font(.caption).pointerCursor()
        }
    }

    private func append(_ value: String, user: Bool = false) { messages.append(Message(text: value, fromUser: user)) }
    private func cancel() {
        append("Cancelar lançamento", user: true)
        append("Tudo bem. Nenhum lançamento foi salvo. Posso ajudar com uma nova saída.")
        drafts = []; text = ""; mode = .menu
    }

    private func send() {
        guard canSend else { return }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        append(input, user: true)
        switch mode {
        case .capture: extract(input)
        case .missing(let index, let field):
            switch field {
            case .description: drafts[index].description = String(input.prefix(200))
            case .amount:
                var candidate = drafts[index]
                candidate.amount = input
                guard candidate.decimal != nil else {
                    append("Digite um valor positivo como 42,90, sem símbolos ou cálculos."); return
                }
                drafts[index].amount = input
            case .payment:
                let methods = Set(ExpenseExtraction(text: input).payments.map(\.value))
                guard
                    let method = PaymentMethod(rawValue: input)?.rawValue ?? (methods.count == 1 ? methods.first : nil)
                else { append("Escolha uma das formas de pagamento acima."); return }
                drafts[index].payment = method
            case .date:
                let dates = Set(ExpenseExtraction(text: input).dates.map(\.value))
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX");
                formatter.dateFormat = "yyyy-MM-dd"
                guard dates.count == 1, let value = dates.first, let date = formatter.date(from: value) else {
                    append("Informe uma data como 15/09/2026, hoje ou ontem."); return
                }
                drafts[index].date = date
            }
            advance()
        default: break
        }
    }

    private func advance() {
        for (index, draft) in drafts.enumerated() {
            let field: Field?
            if draft.description.isEmpty {
                field = .description
            } else if draft.decimal == nil {
                field = .amount
            } else if PaymentMethod(rawValue: draft.payment) == nil {
                field = .payment
            } else if draft.date == nil {
                field = .date
            } else {
                field = nil
            }
            if let field {
                mode = .missing(index, field)
                let question: String
                switch field {
                case .description: question = "Qual é a descrição deste gasto?"
                case .amount: question = "Qual foi o valor de \(draft.description)?"
                case .payment: question = "Como você pagou \(draft.description)?"
                case .date: question = "Em que dia você gastou com \(draft.description)?"
                }
                append(question); composerFocused = true; return
            }
        }
        mode = .review
        let summary = drafts.map { draft in
            "• \(draft.description): \(AppFormat.money(NSDecimalNumber(decimal: draft.decimal!).doubleValue))\n  \(draft.category) · \(draft.payment) · \(AppFormat.date.string(from: draft.date!))"
        }.joined(separator: "\n\n")
        let total = NSDecimalNumber(decimal: drafts.compactMap(\.decimal).reduce(0, +)).doubleValue
        append(
            "Confira o que vou registrar em \((destination ?? month).title):\n\n\(summary)\n\nTotal: \(AppFormat.money(total))\n\nCartão vai para a fatura; os outros pagamentos são descontados do saldo, exceto os já incluídos no saldo inicial. Posso salvar?"
        )
    }

    private func extract(_ input: String) {
        busy = true
        let extraction = ExpenseExtraction(text: input)
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
                    Draft(
                        description: item.description,
                        amount: extraction.amounts.first { $0.id == item.amountID }?.value.replacingOccurrences(
                            of: ".", with: ",") ?? "",
                        category: item.category, payment: item.payment,
                        date: extraction.dates.first { $0.id == item.dateID }.flatMap { formatter.date(from: $0.value) }
                    )
                }
                if drafts.isEmpty {
                    append(
                        "Não encontrei gastos realizados nessa mensagem. Me conte a descrição e o valor do que você gastou."
                    )
                } else {
                    advance()
                }
            } catch {
                if !Task.isCancelled {
                    append(
                        "Não consegui interpretar agora: \(error.localizedDescription)\nVocê pode enviar a mensagem novamente para tentar."
                    )
                }
            }
        }
    }

    private func save() {
        guard !saving, !drafts.isEmpty, drafts.allSatisfy(\.valid) else { return }
        saving = true
        append("Confirmar e salvar", user: true)
        do {
            try store.saveExpenseBatch(drafts.map { $0.expense(monthID: (destination ?? month).id) })
            append(
                "Pronto! Salvei \(drafts.count) lançamento(s) em \((destination ?? month).title). Quer registrar outra saída?"
            )
            mode = .completed
            drafts = []
        } catch {
            saving = false
            append("Nenhum lançamento foi salvo: \(error.localizedDescription)\nVocê pode tentar confirmar novamente.")
        }
    }
}
