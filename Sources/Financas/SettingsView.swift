import SwiftUI
#if os(macOS)
import AppKit
#else
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    @State private var editing:RecurringExpense?
    @State private var confirmDeleteMonth=false
    @State private var importDone=false
    @State private var investmentGoal:Double?
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://192.168.0.250:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "qwen3.5:9b"
    @State private var ollamaState: OllamaState = .idle
    @State private var ollamaTask: Task<Void, Never>?
    #if os(iOS)
    @State private var backupDocument: SQLiteBackupDocument?
    @State private var choosingBackup = false
    @State private var confirmImport = false
    #endif

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
                if compact {
                    MobileHeader(title: "Configurações", subtitle: "Recorrências e dados locais") {
                        CircleActionButton(title: "Nova recorrência", systemImage: "plus") { newRecurring() }
                    }
                } else {
                    ScreenHeader("Configurações",subtitle:"Recorrências e dados locais",inset:0) {
                        Button { newRecurring() } label:{Label("Nova recorrência",systemImage:"plus")}
                    }
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
                    }.padding(compact ? 0 : 8)
                }
                GroupBox("Meta de investimento") {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Valor planejado para investir todo mês. Aparece como “Meta do mês” em Investimentos e é descontado do orçamento de gastos variáveis.").foregroundStyle(.secondary)
                        // Shown once loaded: on iPhone the field reads its value only when it appears.
                        if let goal = investmentGoal {
                            HStack {
                                DecimalField("Meta mensal",value:Binding(get:{goal},set:{investmentGoal=$0})).frame(maxWidth:compact ? .infinity : 220)
                                Button("Salvar") { store.saveMonthlyInvestmentGoal(goal) }
                                    .buttonStyle(.bordered).pointerCursor()
                                    .disabled(goal < 0 || goal == store.monthlyInvestmentGoal)
                            }
                        }
                    }.padding(compact ? 0 : 8)
                }
                .onAppear { investmentGoal = store.monthlyInvestmentGoal }
                GroupBox("Backup") {
                    VStack(alignment:.leading,spacing:12){Text("O backup é uma cópia completa do arquivo SQLite. Importar substitui todos os dados atuais.").foregroundStyle(.secondary);HStack{Button(compact ? "Exportar…" : "Exportar backup…",action:exportBackup).pointerCursor();Button(compact ? "Importar…" : "Importar backup…",action:importBackup).pointerCursor()}.buttonStyle(.bordered)}.padding(compact ? 0 : 8)
                }
                GroupBox("Banco de dados") {
                    VStack(alignment:.leading,spacing:8){
                        Text(store.database.url.path).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                        #if os(macOS)
                        Button("Mostrar no Finder"){NSWorkspace.shared.activateFileViewerSelecting([store.database.url])}.pointerCursor()
                        #else
                        Text("No iPhone, o banco fica dentro do app. Ele é mantido ao reinstalar pelo Xcode, mas é apagado se você remover o app. Exporte backups com frequência.").font(.caption).foregroundStyle(.secondary)
                        #endif
                    }.padding(compact ? 0 : 8)
                }
                GroupBox("Conexão com IA") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Teste o servidor Ollama e o modelo configurado.").foregroundStyle(.secondary)
                        AdaptiveStack(vertical: compact, spacing: 8) {
                            TextField("URL do Ollama", text: $ollamaBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .ollamaInput()
                            TextField("Modelo", text: $ollamaModel)
                                .textFieldStyle(.roundedBorder)
                                .ollamaInput()
                                .frame(width: compact ? nil : 170)
                        }
                        HStack(spacing: 10) {
                            Button {
                                testOllama()
                            } label: {
                                Label(ollamaState.isTesting ? "Testando…" : "Testar conexão", systemImage: "network")
                            }
                            .pointerCursor()
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
                    }.padding(compact ? 0 : 8)
                }
                if store.selectedMonth != nil {
                    GroupBox("Zona de risco") { AdaptiveStack(vertical: compact, spacing: 10){Text("Excluir o mês atual e todos os seus lançamentos.");if !compact { Spacer() };Button("Excluir mês…",role:.destructive){confirmDeleteMonth=true}.pointerCursor()}.padding(compact ? 0 : 8) }
                }
            }.padding(compact ? 16 : 24)
        }
        .sheet(item:$editing){RecurringEditor(item:$0)}
        #if os(iOS)
        .fileExporter(isPresented: Binding(get: { backupDocument != nil }, set: { if !$0 { backupDocument = nil } }), document: backupDocument, contentType: .data, defaultFilename: "financas-backup-\(Date.now.formatted(.iso8601.year().month().day())).sqlite") { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
        .confirmationDialog("Substituir todos os dados?", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Escolher backup…", role: .destructive) { choosingBackup = true }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Os dados atuais deste iPhone serão trocados pelos do arquivo. Exporte um backup antes, se precisar.") }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                store.importBackup(from: url)
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        #endif
        .onDisappear { ollamaTask?.cancel() }
        .confirmationDialog("Excluir o mês atual?",isPresented:$confirmDeleteMonth,titleVisibility:.visible){Button("Excluir mês",role:.destructive){store.deleteCurrentMonth()}.pointerCursor();Button("Cancelar",role:.cancel){}.pointerCursor()} message:{Text("Esta ação não pode ser desfeita.")}
    }

    private func newRecurring() { editing=RecurringExpense(id:0,description:"",category:"Outros",amount:0,dueDay:nil,paymentMethod:.pix,notes:"",active:true) }

    #if os(macOS)
    private func exportBackup() {
        let panel=NSSavePanel();panel.nameFieldStringValue="financas-backup.sqlite"
        if panel.runModal() == .OK,let url=panel.url { store.exportBackup(to:url) }
    }
    private func importBackup() {
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url { store.importBackup(from:url) }
    }
    #else
    private func exportBackup() {
        do { backupDocument = try SQLiteBackupDocument(url: store.database.url) }
        catch { store.errorMessage = error.localizedDescription }
    }
    private func importBackup() { confirmImport = true }
    #endif

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
    var body:some View { BrandForm { TextField("Descrição",text:$item.description);DecimalField("Valor previsto",value:$item.amount);Picker("Categoria",selection:$item.category){ForEach(categories,id:\.self){Text($0)}};Picker("Pagamento",selection:$item.paymentMethod){ForEach(PaymentMethod.allCases){Text($0.rawValue).tag($0)}};OptionalIntField("Dia de vencimento",value:$item.dueDay);TextField("Observação",text:$item.notes,axis:.vertical).lineLimit(2...4);Toggle("Ativo",isOn:$item.active);Text(addToCurrentMonth ? "No mês atual, o lançamento será incluído como pendente. A mudança para “Na fatura” é manual; as demais formas serão pagas e descontadas do saldo." : "Alterações na recorrência valem para novos meses. Use “Sincronizar recorrentes” em Gastos para incluir novos itens no mês atual.").font(.caption).foregroundStyle(.secondary);EditorButtons(saveEnabled:canSave,save:save) }.editorSheet(item.id == 0 ? "Nova recorrência" : "Editar recorrência",width:450,saveEnabled:canSave,save:save) }
    private var canSave: Bool { !item.description.isEmpty && item.amount >= 0 }
    private func save() { store.save(item,addToCurrentMonth:addToCurrentMonth);dismiss() }
}

private extension View {
    @ViewBuilder func ollamaInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        #else
        self
        #endif
    }
}

#if os(iOS)
/// A snapshot of the SQLite file handed to the Files app.
struct SQLiteBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let data: Data
    init(url: URL) throws { data = try Data(contentsOf: url) }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif
