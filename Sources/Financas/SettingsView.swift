import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var editing:RecurringExpense?
    @State private var confirmDeleteMonth=false
    @State private var importDone=false
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://192.168.0.250:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "qwen3.5:9b"
    @State private var ollamaState: OllamaState = .idle
    @State private var ollamaTask: Task<Void, Never>?

    private enum OllamaState {
        case idle, testing
        case success(OllamaConnectionResult)
        case failure(String)

        var isTesting: Bool {
            if case .testing = self { return true }
            return false
        }
    }

    private struct RecurringGroup: Identifiable {
        let category: String
        let items: [RecurringExpense]
        var id: String { category }
    }

    private var groupedRecurring: [RecurringGroup] {
        Dictionary(grouping: store.recurring, by: \.category)
            .map { RecurringGroup(category: $0.key, items: $0.value.sorted { $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending }) }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                ScreenHeader("Configurações",subtitle:"Recorrências e dados locais",inset:0) {
                    Button { editing=RecurringExpense(id:0,description:"",category:"Outros",amount:0,dueDay:nil,paymentMethod:.pix,notes:"",active:true) } label:{Label("Nova recorrência",systemImage:"plus")}
                }
                GroupBox("Gastos recorrentes") {
                    VStack(spacing:0) {
                        ForEach(groupedRecurring) { group in
                            Text(group.category.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth:.infinity,alignment:.leading)
                                .padding(.top,12)
                                .padding(.bottom,4)
                            ForEach(group.items) { item in
                                HStack { Image(systemName:item.active ? "checkmark.circle.fill":"pause.circle").foregroundStyle(item.active ? .green:.secondary);VStack(alignment:.leading){Text(item.description);Text("\(item.paymentMethod.rawValue)\(item.dueDay.map{" • dia \($0)"} ?? "")").font(.caption).foregroundStyle(.secondary)};Spacer();Text(AppFormat.money(item.amount, hidden: hideAmounts));CompactActionMenu{CompactMenuItem("Editar"){editing=item};CompactMenuItem(item.active ? "Desativar":"Ativar"){var copy=item;copy.active.toggle();store.save(copy)};CompactMenuItem("Excluir",role:.destructive){store.delete(item)}}}
                                    .padding(.vertical,8)
                                if item.id != group.items.last?.id { Divider() }
                            }
                        }
                    }.padding(8)
                }
                GroupBox("Backup") {
                    VStack(alignment:.leading,spacing:12){Text("O backup é uma cópia completa do arquivo SQLite. Importar substitui todos os dados atuais.").foregroundStyle(.secondary);HStack{Button("Exportar backup…",action:exportBackup);Button("Importar backup…",action:importBackup)}}.padding(8)
                }
                GroupBox("Banco de dados") {
                    VStack(alignment:.leading,spacing:8){Text(store.database.url.path).font(.system(.caption,design:.monospaced)).textSelection(.enabled);Button("Mostrar no Finder"){NSWorkspace.shared.activateFileViewerSelecting([store.database.url])}}.padding(8)
                }
                GroupBox("Conexão com IA") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Teste o servidor Ollama e o modelo configurado.").foregroundStyle(.secondary)
                        HStack {
                            TextField("URL do Ollama", text: $ollamaBaseURL)
                                .textFieldStyle(.roundedBorder)
                            TextField("Modelo", text: $ollamaModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 170)
                        }
                        HStack(spacing: 10) {
                            Button {
                                testOllama()
                            } label: {
                                Label(ollamaState.isTesting ? "Testando…" : "Testar conexão", systemImage: "network")
                            }
                            .disabled(ollamaState.isTesting || ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            switch ollamaState {
                            case .idle: EmptyView()
                            case .testing: ProgressView().controlSize(.small)
                            case .success(let result):
                                Label("Conectado • \(result.latency, format: .number.precision(.fractionLength(1))) s", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failure(let message):
                                Label(message, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                                    .lineLimit(3)
                            }
                        }
                        if case .success(let result) = ollamaState {
                            Text("Modelo respondeu: \"\(result.response)\"")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Modelos no servidor: \(result.availableModels.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }.padding(8)
                }
                if store.selectedMonth != nil {
                    GroupBox("Zona de risco") { HStack{Text("Excluir o mês atual e todos os seus lançamentos.");Spacer();Button("Excluir mês…",role:.destructive){confirmDeleteMonth=true}}.padding(8) }
                }
            }.padding(24)
        }
        .sheet(item:$editing){RecurringEditor(item:$0)}
        .onDisappear { ollamaTask?.cancel() }
        .confirmationDialog("Excluir o mês atual?",isPresented:$confirmDeleteMonth,titleVisibility:.visible){Button("Excluir mês",role:.destructive){store.deleteCurrentMonth()};Button("Cancelar",role:.cancel){}} message:{Text("Esta ação não pode ser desfeita.")}
    }

    private func exportBackup() {
        let panel=NSSavePanel();panel.nameFieldStringValue="financas-backup.sqlite"
        if panel.runModal() == .OK,let url=panel.url { store.exportBackup(to:url) }
    }
    private func importBackup() {
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url { store.importBackup(from:url) }
    }

    private func testOllama() {
        ollamaTask?.cancel()
        ollamaState = .testing
        let baseURL = ollamaBaseURL
        let model = ollamaModel
        ollamaTask = Task {
            do {
                let result = try await OllamaClient().test(baseURL: baseURL, model: model)
                guard !Task.isCancelled else { return }
                ollamaState = .success(result)
            } catch {
                guard !Task.isCancelled else { return }
                ollamaState = .failure(error.localizedDescription)
            }
        }
    }
}

struct RecurringEditor:View {
    @EnvironmentObject private var store:AppStore;@Environment(\.dismiss) private var dismiss;@State var item:RecurringExpense
    var addToCurrentMonth=false
    private let categories=["Moradia","Carro","Saúde","Educação","Assinaturas","SaaS / Projetos","Lazer","Outros"]
    var body:some View { Form { TextField("Descrição",text:$item.description);TextField("Valor previsto",value:$item.amount,format:.number);Picker("Categoria",selection:$item.category){ForEach(categories,id:\.self){Text($0)}};Picker("Pagamento",selection:$item.paymentMethod){ForEach(PaymentMethod.allCases){Text($0.rawValue).tag($0)}};TextField("Dia de vencimento",value:$item.dueDay,format:.number);TextField("Observação",text:$item.notes,axis:.vertical).lineLimit(2...4);Toggle("Ativo",isOn:$item.active);Text(addToCurrentMonth ? "No mês atual, o lançamento será incluído como pendente. A mudança para “Na fatura” é manual; as demais formas serão pagas e descontadas do saldo." : "Alterações na recorrência valem para novos meses. Use “Sincronizar recorrentes” em Gastos para incluir novos itens no mês atual.").font(.caption).foregroundStyle(.secondary);EditorButtons(saveEnabled:!item.description.isEmpty && item.amount >= 0){store.save(item,addToCurrentMonth:addToCurrentMonth);dismiss()} }.padding().frame(width:450) }
}
