import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

enum AppSection: String, CaseIterable, Identifiable {
    case summary = "Resumo", expenses = "Gastos", outflows = "Saídas", incomes = "Entradas", investments = "Investimentos", settings = "Configurações"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .summary: "rectangle.grid.2x2"
        case .expenses: "creditcard"
        case .outflows: "arrow.up.circle"
        case .incomes: "arrow.down.circle"
        case .investments: "chart.line.uptrend.xyaxis"
        case .settings: "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var section: AppSection? = .summary
    @State private var showingAssistant = false

    var body: some View {
        root
        .environment(\.hideAmounts, hideAmounts)
        .alert("Não foi possível concluir", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage=nil } })) {
            Button("OK") { store.errorMessage=nil }.pointerCursor()
        } message: { Text(store.errorMessage ?? "Erro desconhecido") }
    }

    #if os(iOS)
    private var root: some View { MobileRootView() }
    #else
    private var root: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    BrandMark().frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finanças").font(.system(size: 24, weight: .semibold, design: .serif))
                        Text("Seu dinheiro, com clareza.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 28)
                List(selection: $section) {
                    Section("SEU MÊS") {
                        ForEach(AppSection.allCases.filter { $0 != .settings }) { item in
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.system(size: 14, weight: .medium))
                                .padding(.vertical, 9).tag(item)
                        }
                    }
                    Section {
                        Label(AppSection.settings.rawValue, systemImage: AppSection.settings.icon)
                            .padding(.vertical, 9).tag(AppSection.settings)
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Um mês de cada vez.").font(.system(size: 18, design: .serif))
                    Text("Espaço para planejar o que vem depois.").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            SectionScreen(section: section ?? .summary)
            .toolbar { MonthToolbar() }
            .overlay(alignment: .bottomTrailing) {
                if showingAssistant, let month = store.selectedMonth {
                    AIExpenseView(isPresented: $showingAssistant, month: month)
                        .padding(.trailing, 22).padding(.bottom, 22)
                } else {
                    Button { showingAssistant = true } label: {
                    Image(systemName: "message.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.plain).pointerCursor()
                    .foregroundStyle(AppBrand.forest)
                    .background(AppBrand.mint, in: Circle())
                    .shadow(radius: 10, y: 4)
                    .help("Abrir assistente")
                    .padding(.trailing, 22).padding(.bottom, 22)
                }
            }
            .zIndex(100)
        }
    }
    #endif
}

/// One main screen with the shared brand chrome, used by the Mac detail column and each iOS tab.
struct SectionScreen: View {
    let section: AppSection
    var body: some View {
        Group {
            switch section {
            case .summary: DashboardView()
            case .expenses: ExpensesView()
            case .outflows: ExpensesView(mode: .outflows)
            case .incomes: IncomesView()
            case .investments: InvestmentsView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { BrandBackground() }
        .groupBoxStyle(BrandGroupBoxStyle())
        .scrollContentBackground(.hidden)
    }
}

#if os(iOS)
/// The phone's four destinations. Fixed expenses and one-off outflows share the Gastos tab.
enum MobileTab: String, CaseIterable, Identifiable {
    case summary = "Resumo", expenses = "Gastos", incomes = "Entradas", investments = "Investimentos"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .summary: "rectangle.grid.2x2"
        case .expenses: "creditcard"
        case .incomes: "arrow.down.circle"
        case .investments: "chart.line.uptrend.xyaxis"
        }
    }
}

/// Quick actions offered by the center button and the home screen widget.
private enum QuickAction: String, Identifiable {
    case outflow, income, assistant, recurring, investment
    var id: Self { self }
}

/// Carries a `financas://new/<action>` link from the widget to the tab root, which may not
/// exist yet when the app is launched by the link.
final class QuickActionRouter: ObservableObject {
    @Published var pending: String?

    /// `financas://new/outflow|income|investment` opens a form; `financas://open/summary` the summary.
    func open(_ url: URL) {
        guard url.scheme == "financas", url.host == "new" || url.host == "open" else { return }
        pending = url.lastPathComponent
    }
}

/// iPhone and iPad: swipeable main screens under a custom tab bar with a raised add button
/// in the middle, and month, privacy and settings in the navigation bar.
private struct MobileRootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: QuickActionRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab: MobileTab = .summary
    @State private var showingActions = false
    @State private var pendingAction: QuickAction?
    @State private var action: QuickAction?

    var body: some View {
        TabView(selection: $tab) {
            ForEach(MobileTab.allCases) { item in
                NavigationStack {
                    screen(item)
                        .toolbar { MobileToolbar() }
                        .navigationBarTitleDisplayMode(.inline)
                        .clearsTabBar()
                }
                .tag(item)
            }
        }
        // Swipe sideways between the main screens; the custom bar below replaces the page dots.
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background { BrandBackground() }
        .overlay(alignment: .bottom) {
            MobileTabBar(selection: $tab, addIsOpen: showingActions) { showingActions = true }
        }
        .environment(\.compactLayout, sizeClass == .compact)
        .onAppear(perform: openPendingAction)
        .onChange(of: router.pending) { _, _ in openPendingAction() }
        .sheet(isPresented: $showingActions, onDismiss: {
            action = pendingAction
            pendingAction = nil
        }) {
            QuickActionsSheet { choice in
                pendingAction = choice
                showingActions = false
            }
        }
        .sheet(item: $action) { choice in
            if let month = store.selectedMonth {
                actionSheet(choice, month: month)
                    .environment(\.compactLayout, sizeClass == .compact)
            }
        }
    }

    private func openPendingAction() {
        guard let pending = router.pending else { return }
        router.pending = nil
        if pending == "summary" {
            showingActions = false
            action = nil
            withAnimation(.snappy) { tab = .summary }
            return
        }
        guard let choice = QuickAction(rawValue: pending) else { return }
        showingActions = false
        action = choice
    }

    @ViewBuilder private func screen(_ item: MobileTab) -> some View {
        switch item {
        case .summary: SectionScreen(section: .summary)
        case .expenses: ExpensesTab()
        case .incomes: SectionScreen(section: .incomes)
        case .investments: SectionScreen(section: .investments)
        }
    }

    @ViewBuilder private func actionSheet(_ choice: QuickAction, month: BudgetMonth) -> some View {
        switch choice {
        case .outflow:
            ExpenseEditor(item: Expense(id: 0, monthID: month.id, recurringID: nil, date: .now, description: "", category: "Outros", amount: 0, paymentMethod: .pix, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false))
        case .income:
            IncomeEditor(item: Income(id: 0, monthID: month.id, date: .now, description: "", category: "Outros", amount: 0, expectedDay: nil, status: .pending, isFixed: false))
        case .recurring:
            RecurringEditor(item: RecurringExpense(id: 0, description: "", category: "Outros", amount: 0, dueDay: nil, paymentMethod: .pix, notes: "", active: true), addToCurrentMonth: true)
        case .investment:
            if let fund = store.investmentFunds.first {
                InvestmentMovementEditor(item: InvestmentMovement(id: 0, monthID: month.id, fundID: fund.id, date: .now, kind: .contribution, amount: 0, notes: ""))
            }
        case .assistant:
            AIExpenseView(isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), month: month)
        }
    }
}

/// Gastos tab: one-off outflows and fixed expenses behind a single switch.
private struct ExpensesTab: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case outflows = "Do mês", fixed = "Fixos"
        var id: String { rawValue }
    }
    @State private var kind: Kind = .outflows

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tipo de gasto", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
            switch kind {
            case .outflows: SectionScreen(section: .outflows)
            case .fixed: SectionScreen(section: .expenses)
            }
        }
        .background { BrandBackground() }
    }
}

extension View {
    /// Room for the floating tab bar, so the last card can scroll clear of it. Every screen shown
    /// under the bar needs it, including ones pushed onto a tab's navigation stack.
    func clearsTabBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: MobileTabBar.height + 12) }
    }
}

/// Four tabs around a raised mint add button, on a floating glass capsule.
private struct MobileTabBar: View {
    static let height: CGFloat = 62
    @Binding var selection: MobileTab
    var addIsOpen = false
    let onAdd: () -> Void
    @Namespace private var indicator
    @State private var bounce: [MobileTab: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            item(.summary)
            item(.expenses)
            Color.clear.frame(maxWidth: .infinity)
            item(.incomes)
            item(.investments)
        }
        .padding(.horizontal, 6)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: selection)
        .frame(height: Self.height)
        .modifier(TabBarBackground())
        // Outside the glass, so the button stays solid instead of picking up the glass's translucency.
        .overlay {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .rotationEffect(.degrees(addIsOpen ? 45 : 0))
                    .foregroundStyle(AppBrand.forest)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle().fill(LinearGradient(colors: [AppBrand.mint, Color(red: 0.62, green: 0.85, blue: 0.52)], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                    .shadow(color: AppBrand.forest.opacity(0.35), radius: 12, y: 6)
                    .scaleEffect(addIsOpen ? 0.92 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: addIsOpen)
            }
            .buttonStyle(PressableStyle())
            .offset(y: -16)
            .sensoryFeedback(.impact(weight: .medium), trigger: addIsOpen) { _, open in open }
            .accessibilityLabel("Registrar")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func item(_ tab: MobileTab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { selection = tab }
            bounce[tab, default: 0] += 1
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 21, weight: selected ? .semibold : .regular))
                .symbolEffect(.bounce, value: bounce[tab, default: 0])
                .foregroundStyle(selected ? AppBrand.accent : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    // A soft pill that slides to the selected tab.
                    if selected {
                        Capsule()
                            .fill(AppBrand.accent.opacity(0.13))
                            .frame(width: 54, height: 40)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TabBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
    }
}

/// The add button's menu: the two everyday entries up front, the rest below.
private struct QuickActionsSheet: View {
    let choose: (QuickAction) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Registrar").font(.headline).foregroundStyle(.white).padding(.top, 22)
            HStack(spacing: 12) {
                tile("Saída", "arrow.up.circle.fill", .outflow).entrance(0)
                tile("Entrada", "arrow.down.circle.fill", .income).entrance(1)
            }
            VStack(spacing: 0) {
                row("Registrar com o assistente", "sparkles", .assistant)
                Divider().overlay(.white.opacity(0.1))
                row("Novo gasto fixo", "repeat", .recurring)
                Divider().overlay(.white.opacity(0.1))
                row("Aporte ou resgate", "chart.line.uptrend.xyaxis", .investment)
            }
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .entrance(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .editorChrome()
        .presentationDetents([.height(380)])
    }

    private func tile(_ title: String, _ icon: String, _ action: QuickAction) -> some View {
        Button { choose(action) } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 30))
                Text(title).font(.headline)
            }
            .foregroundStyle(AppBrand.forest)
            .frame(maxWidth: .infinity).frame(height: 104)
            .background(AppBrand.mint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func row(_ title: String, _ icon: String, _ action: QuickAction) -> some View {
        Button { choose(action) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(AppBrand.mint)
                Text(title).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16).frame(height: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MobileToolbar: ToolbarContent {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hideAmounts") private var hideAmounts = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Mês", selection: Binding(get: { store.selectedMonthID ?? 0 }, set: store.select)) {
                    ForEach(store.months.reversed()) { Text($0.title).tag($0.id) }
                }
                Divider()
                Button { store.createNextMonth() } label: { Label("Novo mês", systemImage: "calendar.badge.plus") }
            } label: {
                HStack(spacing: 4) {
                    Text(store.selectedMonth?.title ?? "Mês").font(.headline).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
            }
            .accessibilityLabel("Mês")
            .accessibilityValue(store.selectedMonth?.title ?? "")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { hideAmounts.toggle() } label: {
                Label(hideAmounts ? "Mostrar valores" : "Ocultar valores", systemImage: hideAmounts ? "eye.slash" : "eye")
            }
            NavigationLink {
                SectionScreen(section: .settings).navigationBarTitleDisplayMode(.inline).clearsTabBar()
            } label: {
                Label(AppSection.settings.rawValue, systemImage: AppSection.settings.icon)
            }
        }
    }
}
#endif

struct MonthToolbar: ToolbarContent {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hideAmounts") private var hideAmounts = false
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                hideAmounts.toggle()
            } label: {
                Label(hideAmounts ? "Mostrar valores" : "Ocultar valores", systemImage: hideAmounts ? "eye.slash" : "eye")
            }
            .help(hideAmounts ? "Mostrar valores" : "Ocultar valores")
        }
        ToolbarItem(placement: .automatic) {
            Picker("Mês", selection: Binding(get: { store.selectedMonthID ?? 0 }, set: store.select)) {
                ForEach(store.months) { Text($0.title).tag($0.id) }
            }.frame(width: 180)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { store.createNextMonth() } label: { Label("Novo mês", systemImage: "plus") }
        }
    }
}

struct EmptyMonthView: View {
    var body: some View { ContentUnavailableView("Nenhum mês", systemImage: "calendar", description: Text("Crie um mês para começar.")) }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    @State private var editingBalance = false
    @State private var hoveredCategory:String?
    @State private var selectedCategory:String?
    @State private var chartRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    private struct CategorySpending:Identifiable {
        let category:String
        let items:[Expense]
        var total:Double { items.reduce(0) { $0 + $1.amount } }
        var id:String { category }
    }

    private var spendingByCategory:[CategorySpending] {
        let spent=store.expenses.filter { [.paid,.prepaid,.invoice].contains($0.status) }
        return Dictionary(grouping:spent,by:\.category)
            .map { CategorySpending(category:$0.key,items:$0.value.sorted { $0.amount > $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var totalCategorySpending:Double { spendingByCategory.reduce(0) { $0 + $1.total } }
    private var activeCategory:String? { selectedCategory ?? hoveredCategory }
    private var highlightedCategory:String? { activeCategory }
    private var activeSpending:CategorySpending? {
        guard let activeCategory else { return nil }
        return spendingByCategory.first { $0.category == activeCategory }
    }
    private func categoryPercentage(_ item:CategorySpending) -> Int {
        Int((item.total / totalCategorySpending * 100).rounded())
    }

    var body: some View {
        if let month = store.selectedMonth {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading) {
                            if !compact { Text("VISÃO GERAL").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary) }
                            Text(month.title).font(.system(size: compact ? 28 : 34, weight: .medium, design: .serif))
                                .lineLimit(1).minimumScaleFactor(0.8)
                            if !compact { Text("Seu mês em perspectiva.").foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if compact {
                            Button { editingBalance=true } label: {
                                Image(systemName: "pencil").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppBrand.forest)
                            .background(AppBrand.mint, in: Circle())
                            .accessibilityLabel("Editar saldos")
                        } else {
                            Button("Editar saldos") { editingBalance=true }
                                .buttonStyle(.plain).pointerCursor()
                                .foregroundStyle(AppBrand.forest)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(AppBrand.mint, in: Capsule())
                                .contentShape(Capsule())
                        }
                    }
                    .entrance(0)
                    HStack(alignment: .center, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("SALDO ATUAL", systemImage: "wallet.bifold").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(AppBrand.mint)
                            AnimatedMoney(value: month.currentBalance, hidden: hideAmounts)
                                .font(.system(size: compact ? 36 : 44, weight: .medium, design: .rounded)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.65)
                            Text("Saldo inicial de \(AppFormat.money(month.initialBalance, hidden: hideAmounts))")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer(minLength: 0)
                        if !compact { BrandMark().frame(width: 100, height: 100) }
                    }
                    .padding(compact ? 20 : 28).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .background { HeroBackground(cornerRadius: 24) }
                    .entrance(1)
                    // Extra air around the hero on the phone; its shadow also eats into the gap below.
                    .padding(.top, compact ? 10 : 0)
                    .padding(.bottom, compact ? 10 : 0)
                    if compact {
                        phoneMetrics
                    } else {
                    LazyVGrid(columns:columns,spacing:16) {
                        MetricCard(
                            "Pendentes",
                            store.totals.pending + store.totals.invoice,
                            "clock",
                            color: .orange,
                            size: .featured,
                            caption: "Pendentes: \(AppFormat.money(store.totals.pending, hidden: hideAmounts)) • Na fatura: \(AppFormat.money(store.totals.invoice, hidden: hideAmounts))"
                        )
                        .entrance(2)
                        ExpectedIncomeCard(total: store.incomes.filter { $0.status == .pending }.reduce(0) { $0 + $1.amount }, salary: store.nextSalary())
                            .entrance(3)
                        MetricCard(
                            "Investido no mês",
                            store.totals.investmentsActual,
                            "chart.line.uptrend.xyaxis",
                            color: .purple,
                            size: .featured,
                            caption: "de \(AppFormat.money(store.totals.investmentsPlanned, hidden: hideAmounts)) planejados"
                        )
                        .entrance(4)
                    }
                    }
                    GroupBox("Gastos por categoria") {
                        if spendingByCategory.isEmpty {
                            ContentUnavailableView("Nenhum gasto realizado",systemImage:"chart.pie",description:Text("Gastos pagos ou na fatura aparecerão aqui."))
                                .frame(height:220)
                        } else {
                            VStack(alignment:.leading,spacing:8) {
                                Text("Pagos, pagos antecipadamente e na fatura • Total \(AppFormat.money(totalCategorySpending,hidden:hideAmounts))")
                                    .font(.caption).foregroundStyle(.secondary)
                                AdaptiveStack(vertical: compact, spacing: 20) {
                                    Chart(spendingByCategory) { item in
                                            SectorMark(
                                                angle:.value("Valor",item.total),
                                                innerRadius:.ratio(0.64),
                                                outerRadius:.ratio(highlightedCategory == item.category ? 1 : 0.94),
                                                angularInset:1.5
                                            )
                                            .cornerRadius(3)
                                            .foregroundStyle(by:.value("Categoria",item.category))
                                            .opacity(highlightedCategory == nil || highlightedCategory == item.category ? 1 : 0.48)
                                            .annotation(position:.overlay) {
                                            if item.total / totalCategorySpending >= 0.08 {
                                                Text("\(categoryPercentage(item))%")
                                                    .font(.caption.bold()).foregroundStyle(.white)
                                            }
                                        }
                                    }
                                    .chartLegend(position:.bottom,alignment:.leading,spacing:8)
                                    .chartForegroundStyleScale(
                                        domain: spendingByCategory.map(\.category),
                                        range: spendingByCategory.indices.map { AppBrand.chartColors[$0 % AppBrand.chartColors.count] }
                                    )
                                    .chartOverlay { proxy in
                                        CategoryChartOverlay(proxy: proxy) { value in
                                            hoveredCategory = value.flatMap { category(at: $0) }
                                        } onSelect: { value in
                                            guard let value, let category = category(at: value) else {
                                                selectedCategory = nil
                                                hoveredCategory = nil
                                                return
                                            }
                                            selectedCategory = category
                                            hoveredCategory = category
                                        }
                                    }
                                    .frame(minWidth:240,minHeight:compact ? 280 : 300)
                                    // The ring spins and grows into place the first time it appears.
                                    .rotationEffect(.degrees(chartRevealed || reduceMotion ? 0 : -120))
                                    .scaleEffect(chartRevealed || reduceMotion ? 1 : 0.6)
                                    .opacity(chartRevealed || reduceMotion ? 1 : 0)
                                    .onAppear {
                                        withAnimation(.spring(response: 0.9, dampingFraction: 0.78).delay(0.25)) { chartRevealed = true }
                                    }
                                    GroupBox {
                                        if let selected=activeSpending {
                                            VStack(alignment:.leading,spacing:7) {
                                                HStack {
                                                    Text(selected.category).font(.headline)
                                                    Spacer()
                                                    Text(AppFormat.money(selected.total,hidden:hideAmounts)).font(.headline).monospacedDigit()
                                                    if selectedCategory != nil {
                                                        Button { selectedCategory=nil; hoveredCategory=nil } label: {
                                                            Image(systemName:"xmark.circle.fill")
                                                        }
                                                        .buttonStyle(.plain).pointerCursor()
                                                        .foregroundStyle(.secondary)
                                                        .help("Fechar categoria")
                                                    }
                                                }
                                                Text(selectedCategory == nil ? "\(categoryPercentage(selected))% do total" : "\(categoryPercentage(selected))% do total • \(compact ? "Toque" : "Clique") em outra fatia para trocar")
                                                    .font(.caption).foregroundStyle(.secondary)
                                                Divider()
                                                ScrollView(.vertical) {
                                                    VStack(spacing:6) {
                                                        ForEach(selected.items) { expense in
                                                            HStack {
                                                                VStack(alignment:.leading) {
                                                                    Text(expense.description)
                                                                    Text(expense.status.rawValue).font(.caption).foregroundStyle(.secondary)
                                                                }
                                                                Spacer()
                                                                Text(AppFormat.money(expense.amount,hidden:hideAmounts)).monospacedDigit()
                                                            }
                                                        }
                                                    }
                                                }
                                                .frame(maxHeight:220)
                                            }
                                        } else {
                                            ContentUnavailableView(compact ? "Toque em uma fatia" : "Clique em uma fatia",systemImage:compact ? "hand.tap" : "cursorarrow.click",description:Text("O painel ficará fixo com os gastos da categoria e poderá ser rolado."))
                                        }
                                    }.frame(width:compact ? nil : 260).frame(maxWidth:compact ? .infinity : nil).frame(minHeight:260,maxHeight:320)
                                }
                            }.padding(compact ? 0 : 8)
                        }
                    }
                    .entrance(5)
                }.padding(compact ? 16 : 24)
            }.sheet(isPresented: $editingBalance) { MonthEditor(month: month) }
        } else { EmptyMonthView() }
    }

    /// iPhone: pending and expected income side by side, the month's investing below.
    private var phoneMetrics: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                SummaryTile(title: "Pendentes", symbol: "clock", color: .orange,
                            value: store.totals.pending + store.totals.invoice,
                            lines: ["A pagar \(AppFormat.money(store.totals.pending, hidden: hideAmounts))",
                                    "Fatura \(AppFormat.money(store.totals.invoice, hidden: hideAmounts))"])
                    .entrance(2)
                let salary = store.nextSalary()
                SummaryTile(title: "A receber", symbol: "calendar.badge.clock", color: AppBrand.accent,
                            value: store.incomes.filter { $0.status == .pending }.reduce(0) { $0 + $1.amount },
                            lines: salary.map { ["Próxima \($0.days == 0 ? "hoje" : "em \($0.days) \($0.days == 1 ? "dia" : "dias")")",
                                                 "\(AppFormat.money($0.amount, hidden: hideAmounts)) • \($0.date.formatted(.dateTime.day().month(.twoDigits)))"] }
                                   ?? ["Nenhuma entrada fixa pendente"])
                    .entrance(3)
            }
            .fixedSize(horizontal: false, vertical: true)
            MetricCard(
                "Investido no mês",
                store.totals.investmentsActual,
                "chart.line.uptrend.xyaxis",
                color: .purple,
                size: .featured,
                caption: "de \(AppFormat.money(store.totals.investmentsPlanned, hidden: hideAmounts)) planejados"
            )
            .entrance(4)
        }
    }

    private func category(at angleValue:Double)->String? {
        var accumulated=0.0
        for item in spendingByCategory {
            accumulated += item.total
            if angleValue <= accumulated { return item.category }
        }
        return spendingByCategory.last?.category
    }
}

private struct CategoryChartOverlay: View {
    let proxy: ChartProxy
    let onHover: (Double?) -> Void
    let onSelect: (Double?) -> Void

    init(proxy: ChartProxy, onHover: @escaping (Double?) -> Void, onSelect: @escaping (Double?) -> Void) {
        self.proxy = proxy
        self.onHover = onHover
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let value = value(at: location, in: geometry)
                        #if os(macOS)
                        if value == nil {
                            NSCursor.arrow.set()
                        } else {
                            NSCursor.pointingHand.set()
                        }
                        #endif
                        onHover(value)
                    case .ended:
                        #if os(macOS)
                        NSCursor.arrow.set()
                        #endif
                        onHover(nil)
                    }
                }
                .gesture(SpatialTapGesture().onEnded { event in
                    onSelect(value(at: event.location, in: geometry))
                })
        }
    }

    private func value(at location: CGPoint, in geometry: GeometryProxy) -> Double? {
        guard let anchor = proxy.plotFrame else { return nil }
        let frame = geometry[anchor]
        let point = CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let distance = hypot(point.x - center.x, point.y - center.y)
        let radius = min(frame.width, frame.height) / 2
        guard distance >= radius * 0.42, distance <= radius * 1.05 else { return nil }
        return proxy.value(atAngle: proxy.angle(at: point))
    }
}

struct ExpectedIncomeCard: View {
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    let total: Double
    let salary:NextSalary?
    var body:some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment:.top) {
                BrandIcon(symbol: "calendar.badge.clock")
                VStack(alignment:.leading,spacing:6) {
                    Text("Entradas previstas").font(.subheadline).foregroundStyle(.secondary)
                    AnimatedMoney(value: total, hidden: hideAmounts)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    if let salary {
                        Text("Próximo salário: \(salary.days == 0 ? "hoje" : "em \(salary.days) \(salary.days == 1 ? "dia" : "dias")")")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("\(AppFormat.money(salary.amount,hidden:hideAmounts)) • \(AppFormat.date.string(from:salary.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Nenhum salário pendente").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(20).frame(maxWidth:.infinity, minHeight:compact ? nil : 160, maxHeight:compact ? nil : 160)
            .brandSurface()
    }
}

/// A half-width card for the phone dashboard: icon, title, amount and two short lines.
private struct SummaryTile: View {
    @Environment(\.hideAmounts) private var hideAmounts
    let title: String
    let symbol: String
    let color: Color
    let value: Double
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            AnimatedMoney(value: value, hidden: hideAmounts)
                .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .brandSurface()
    }
}

struct MetricCard: View {
    enum Size { case compact, featured }
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compactLayout
    let title: String; let value: Double; let icon: String; let color: Color; let size: Size; let caption: String?
    init(_ title: String, _ value: Double, _ icon: String, color: Color = .accentColor, size: Size = .compact, caption: String? = nil) {
        self.title=title; self.value=value; self.icon=icon; self.color=color; self.size=size; self.caption=caption
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                BrandIcon(symbol: icon, color: color)
            }
            AnimatedMoney(value: value, hidden: hideAmounts)
                .font(.system(size: size == .featured ? 27 : 22, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: compactLayout ? nil : 160, maxHeight: compactLayout ? nil : 160, alignment: .topLeading)
        .brandSurface()
    }
}

struct MonthEditor: View {
    @EnvironmentObject private var store:AppStore; @Environment(\.dismiss) private var dismiss
    @State var month:BudgetMonth
    var body:some View {
        BrandForm {
            DecimalField("Saldo inicial",value:$month.initialBalance);DecimalField("Saldo atual",value:$month.currentBalance)
            Text("O saldo atual é atualizado ao receber entradas, pagar gastos ou realizar investimentos. Edite-o apenas para conciliar com a conta.").font(.caption).foregroundStyle(.secondary)
            Toggle("Informar data",isOn:Binding(get:{month.balanceDate != nil},set:{month.balanceDate = $0 ? .now:nil}))
            if month.balanceDate != nil { DatePicker("Data do saldo",selection:Binding(get:{month.balanceDate ?? .now},set:{month.balanceDate=$0}),displayedComponents:.date) }
            #if os(macOS)
            HStack{Spacer();Button("Cancelar"){dismiss()}.buttonStyle(.bordered).pointerCursor();Button("Salvar",action:save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).pointerCursor()}
            #endif
        }.editorSheet("Editar saldos",width:420,save:save)
    }
    private func save() { store.saveMonth(month);dismiss() }
}

/// Side by side on wide screens, stacked on iPhone.
struct AdaptiveStack<Content: View>: View {
    let vertical: Bool
    var spacing: CGFloat = 16
    @ViewBuilder let content: () -> Content
    var body: some View {
        if vertical { VStack(alignment: .leading, spacing: spacing, content: content) }
        else { HStack(spacing: spacing, content: content) }
    }
}
