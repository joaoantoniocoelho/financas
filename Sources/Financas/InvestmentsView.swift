import SwiftUI

struct InvestmentsView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    @State private var editing:InvestmentMovement?
    @State private var editingFund:InvestmentFund?
    @State private var deletingFund:InvestmentFund?
    @State private var page:InvestmentPage? = .reais
    private let columns=[GridItem(.adaptive(minimum:230),spacing:12)]

    var body:some View {
        if let month=store.selectedMonth {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if compact {
                        MobileHeader(title: "Investimentos", subtitle: "Fundos, aportes e resgates") {
                            CircleActionButton(title: "Novo investimento", systemImage: "building.columns", prominent: false) { newFund() }
                            CircleActionButton(title: "Nova movimentação", systemImage: "plus") { newMovement(month) }
                        }
                        .entrance(0)
                    } else {
                        ScreenHeader("Investimentos",subtitle:"Acompanhe seus fundos, aportes e resgates",inset:0) {
                            Button { newMovement(month) } label:{ Label("Nova movimentação",systemImage:"plus") }
                            Button { newFund() } label:{ Label("Novo investimento",systemImage:"building.columns") }
                        }
                    }

                    carousel.entrance(1)

                    EmergencyReserveCard(funds:store.emergencyReserveFunds,balance:store.emergencyReserveBalance,fixedExpenses:store.monthlyFixedExpenseBaseline,months:store.emergencyReserveMonths)
                        .entrance(2)

                    GroupBox {
                        if pageFunds.isEmpty {
                            ContentUnavailableView("Nenhum investimento em reais",systemImage:"building.columns",description:Text("Cadastre fundos, ações ou objetivos para acompanhar os saldos."))
                                .frame(height:170)
                        } else {
                            LazyVGrid(columns:columns,spacing:12) {
                                ForEach(pageFunds.prefix(Self.previewCount)) { fund in
                                    FundCard(fund:fund) { editingFund=fund } delete:{ deletingFund=fund }
                                }
                            }.padding(compact ? 0 : 6)
                        }
                    } label: {
                        HStack {
                            Text(activePage.listTitle)
                                .contentTransition(.opacity)
                            Spacer()
                            if !store.investmentFunds.isEmpty {
                                NavigationLink { InvestmentFundsListView() } label: {
                                    Image(systemName:"chevron.right")
                                        .font(.system(size:13,weight:.bold))
                                        .frame(width:30,height:30)
                                        .background(AppBrand.accent.opacity(0.12),in:Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain).pointerCursor()
                                .accessibilityLabel("Ver todos os investimentos")
                            }
                        }
                    }
                    .entrance(3)

                    GroupBox("Movimentações de \(month.title)") {
                        if store.investmentMovements.isEmpty {
                            ContentUnavailableView("Nenhuma movimentação neste mês",systemImage:"arrow.left.arrow.right",description:Text("Registre um aporte ou resgate e escolha em qual fundo ele aconteceu."))
                                .frame(height:170)
                        } else {
                            VStack(spacing:0) {
                                ForEach(store.investmentMovements) { movement in
                                    InvestmentMovementRow(movement:movement,fundName:store.investmentFunds.first(where:{$0.id == movement.fundID})?.name ?? "Fundo") {
                                        editing=movement
                                    } delete:{ store.delete(movement) }
                                    if movement.id != store.investmentMovements.last?.id { Divider() }
                                }
                            }.padding(.horizontal,compact ? 0 : 8)
                        }
                    }
                    .entrance(4)
                }.padding(compact ? 16 : 24)
            }
            .sheet(item:$editing) { InvestmentMovementEditor(item:$0) }
            .fundActions(editing:$editingFund,deleting:$deletingFund)
        } else { EmptyMonthView() }
    }

    /// The totals in reais first, then one page per foreign currency. Balances in different currencies
    /// never add up, so each gets its own page, and the fund list below follows the visible one.
    private var pages:[InvestmentPage] { [.reais] + store.foreignHoldings.map { .foreign($0.currency) } }
    private var activePage:InvestmentPage { page.flatMap { pages.contains($0) ? $0 : nil } ?? .reais }
    private var pageFunds:[InvestmentFund] {
        switch activePage {
        case .reais: store.realFunds
        case .foreign(let currency): store.investmentFunds.filter { $0.foreignCurrency == currency }
        }
    }

    @ViewBuilder private var carousel:some View {
        if pages.count == 1 {
            reaisPage
        } else {
            VStack(spacing:10) {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(alignment:.top,spacing:12) {
                        ForEach(pages) { page in
                            pageView(page).containerRelativeFrame(.horizontal).id(page)
                        }
                    }
                    // Pages share the tallest one's height, so the cards line up while swiping.
                    .fixedSize(horizontal:false,vertical:true)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id:$page)
                PageDots(pages:pages,active:activePage) { target in withAnimation(.snappy) { page=target } }
            }
            .animation(.snappy,value:activePage)
        }
    }

    @ViewBuilder private func pageView(_ page:InvestmentPage) -> some View {
        switch page {
        case .reais: reaisPage
        case .foreign(let currency):
            if let holding=store.foreignHoldings.first(where:{$0.currency == currency}) {
                ForeignCurrencyCard(currency:currency,count:holding.funds.count,total:holding.total)
            }
        }
    }

    @ViewBuilder private var reaisPage:some View {
        if compact {
            heroCard
        } else {
            LazyVGrid(columns:columns,spacing:12) {
                MetricCard("Total investido",store.totalInvested,"chart.line.uptrend.xyaxis",color:.green,size:.featured)
                MetricCard("Meta do mês",store.totals.investmentsPlanned,"target",size:.featured)
                MetricCard("Aportado no mês",store.totals.investmentsActual,"arrow.up.circle",color:.green,size:.featured)
            }
        }
    }

    /// iPhone: the invested total up front, with the month's goal and contributions below.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VALOR INVESTIDO").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(AppBrand.mint)
                AnimatedMoney(value: store.totalInvested, hidden: hideAmounts)
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 8) {
                ForEach([("Meta do mês", store.totals.investmentsPlanned), ("Aportado no mês", store.totals.investmentsActual)], id: \.0) { title, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                        AnimatedMoney(value: value, hidden: hideAmounts).font(.footnote.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HeroBackground() }
    }

    /// The card shows only the first few; the chevron opens the full list.
    static let previewCount = 3

    private func newMovement(_ month: BudgetMonth) {
        guard let fund=store.realFunds.first else { newFund(); return }
        editing=InvestmentMovement(id:0,monthID:month.id,fundID:fund.id,date:.now,kind:.contribution,amount:0,notes:"")
    }

    private func newFund() { editingFund = .new }
}

/// Every investment, filterable by type. The grid is lazy, so long lists scroll smoothly.
struct InvestmentFundsListView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.compactLayout) private var compact
    @State private var filter:FundFilter = .all
    @State private var editingFund:InvestmentFund?
    @State private var deletingFund:InvestmentFund?
    private let columns=[GridItem(.adaptive(minimum:230),spacing:12)]

    private var activeFilter:FundFilter { filter.resolved(in:store.investmentFunds) }
    private var filteredFunds:[InvestmentFund] { activeFilter.apply(to:store.investmentFunds) }

    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:18) {
                if compact {
                    MobileHeader(title:"Seus investimentos",subtitle:"\(store.investmentFunds.count) cadastrados") {
                        CircleActionButton(title:"Novo investimento",systemImage:"plus") { editingFund = .new }
                    }
                } else {
                    ScreenHeader("Seus investimentos",subtitle:"\(store.investmentFunds.count) investimentos cadastrados",inset:0) {
                        Button { editingFund = .new } label:{ Label("Novo investimento",systemImage:"plus") }
                    }
                }
                FundFilterBar(filter:$filter,funds:store.investmentFunds)
                FundTypeTotal(filter:activeFilter,funds:filteredFunds)
                if filteredFunds.isEmpty {
                    ContentUnavailableView("Nenhum investimento cadastrado",systemImage:"building.columns",description:Text("Cadastre fundos, ações, moeda estrangeira ou objetivos para acompanhar os saldos."))
                        .frame(height:220)
                } else {
                    LazyVGrid(columns:columns,spacing:12) {
                        ForEach(filteredFunds) { fund in
                            FundCard(fund:fund) { editingFund=fund } delete:{ deletingFund=fund }
                        }
                    }
                }
            }.padding(compact ? 16 : 24)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .background { BrandBackground() }
        .scrollContentBackground(.hidden)
        .fundActions(editing:$editingFund,deleting:$deletingFund)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .clearsTabBar()
        #endif
    }
}

private enum FundFilter:Hashable,Identifiable {
    case all
    case type(InvestmentAssetType)
    var id:String { title }
    var title:String {
        switch self {
        case .all: "Todos"
        case .type(let type): type.rawValue
        }
    }

    /// "Todos" plus only the types that have at least one investment.
    static func options(for funds:[InvestmentFund]) -> [FundFilter] {
        let present=Set(funds.map(\.assetType))
        return [.all] + InvestmentAssetType.allCases.filter(present.contains).map(FundFilter.type)
    }

    /// Falls back to "Todos" when the last investment of the chosen type is deleted or changes type.
    func resolved(in funds:[InvestmentFund]) -> FundFilter { Self.options(for:funds).contains(self) ? self : .all }

    func apply(to funds:[InvestmentFund]) -> [InvestmentFund] {
        guard case .type(let type) = self else { return funds }
        return funds.filter { $0.assetType == type }
    }
}

/// Chips on iPhone, a menu on the Mac. Hidden while there's only one type to pick.
private struct FundFilterBar:View {
    @Environment(\.compactLayout) private var compact
    @Binding var filter:FundFilter
    let funds:[InvestmentFund]
    var body:some View {
        let options=FundFilter.options(for:funds)
        let selection=Binding(get:{filter.resolved(in:funds)},set:{filter=$0})
        if options.count > 2 {
            if compact {
                ChipPicker(selection:selection,options:options,title:\.title)
            } else {
                Picker("Tipo",selection:selection) {
                    ForEach(options) { Text($0.title).tag($0) }
                }
                .fixedSize().pointerCursor()
            }
        }
    }
}

private struct FundTypeTotal:View {
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    let filter:FundFilter
    let funds:[InvestmentFund]
    var body:some View {
        if case .type(let type) = filter {
            HStack {
                Text("Total em \(type.rawValue.lowercased())").foregroundStyle(.secondary)
                Spacer()
                Text(totalText).fontWeight(.semibold).monospacedDigit()
            }
            .font(.subheadline).padding(.horizontal,compact ? 0 : 6).padding(.bottom,4)
        }
    }

    /// Balances in different currencies are never added together.
    private var totalText:String {
        Dictionary(grouping:funds,by:\.foreignCurrency)
            .sorted { ($0.key?.rawValue ?? "") < ($1.key?.rawValue ?? "") }
            .map { AppFormat.money($0.value.reduce(0) { $0 + $1.currentBalance },in:$0.key,hidden:hideAmounts) }
            .joined(separator:" + ")
    }
}

private extension InvestmentFund {
    static var new:InvestmentFund { InvestmentFund(id:0,name:"",assetType:.fund,openingBalance:0,currentBalance:0,isEmergencyReserve:false) }
}

private extension View {
    /// The fund editor sheet and the delete confirmation, shared by the overview and the full list.
    func fundActions(editing:Binding<InvestmentFund?>,deleting:Binding<InvestmentFund?>) -> some View {
        modifier(FundActions(editing:editing,deleting:deleting))
    }
}

private struct FundActions:ViewModifier {
    @EnvironmentObject private var store:AppStore
    @Binding var editing:InvestmentFund?
    @Binding var deleting:InvestmentFund?
    func body(content:Content) -> some View {
        content
            .sheet(item:$editing) { InvestmentFundEditor(item:$0) }
            .confirmationDialog("Excluir \(deleting?.name ?? "investimento")?",isPresented:Binding(get:{deleting != nil},set:{ if !$0 { deleting=nil } }),titleVisibility:.visible) {
                Button("Excluir",role:.destructive) { if let fund=deleting { store.delete(fund) }; deleting=nil }
            } message: { Text("O saldo deixa de contar no total investido. Só é possível excluir investimentos sem movimentações.") }
    }
}

private struct EmergencyReserveCard:View {
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    let funds:[InvestmentFund]
    let balance:Double
    let fixedExpenses:Double
    let months:Double
    var body:some View {
        GroupBox {
            AdaptiveStack(vertical: compact, spacing: compact ? 12 : 18) {
                HStack(spacing:compact ? 12 : 18) {
                    ReserveRing(progress: fixedExpenses > 0 ? months / 6 : 0)
                    VStack(alignment:.leading,spacing:4) {
                        Text("Reserva de emergência").font(.headline)
                        Text(funds.isEmpty ? "Nenhum investimento marcado como reserva" : funds.map(\.name).joined(separator:" + "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                if !compact { Spacer() }
                VStack(alignment:compact ? .leading : .trailing,spacing:4) {
                    Text(fixedExpenses > 0 ? "\(months.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR")))) meses" : "—").font(.title.bold()).monospacedDigit()
                    if !funds.isEmpty {
                        Text("\(AppFormat.money(balance,hidden:hideAmounts)) ÷ \(AppFormat.money(fixedExpenses,hidden:hideAmounts)) em gastos fixos mensais")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(compact ? 0 : 10)
        }
    }
}

private struct FundCard:View {
    @Environment(\.hideAmounts) private var hideAmounts
    let fund:InvestmentFund
    let edit:()->Void
    let delete:()->Void
    var body:some View {
        if let currency=fund.foreignCurrency { foreignCard(currency) } else { realCard }
    }

    private var realCard:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top) {
                Image(systemName:fund.assetType.systemImage)
                    .foregroundStyle(fund.isEmergencyReserve ? .green : .accentColor)
                Text(fund.name).font(.headline).lineLimit(2)
                Spacer()
                menu
            }
            Text(AppFormat.money(fund.currentBalance,hidden:hideAmounts)).font(.title2.bold()).monospacedDigit()
            HStack(spacing:6) {
                Text(fund.assetType.rawValue)
                if fund.isEmergencyReserve {
                    Label("Reserva", systemImage:"shield.fill").foregroundStyle(.green)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth:.infinity,minHeight:120,alignment:.leading)
        .background(AppBrand.canvas,in:RoundedRectangle(cornerRadius:16))
        .contentShape(RoundedRectangle(cornerRadius:16)).onTapGesture(perform:edit)
    }

    /// Foreign balances wear their currency's colors, so they never read as reais.
    private func foreignCard(_ currency:ForeignCurrency) -> some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top) {
                Image(systemName:currency.systemImage).foregroundStyle(currency.highlight)
                Text(fund.name).font(.headline).lineLimit(2)
                Spacer()
                menu.tint(.white)
            }
            Text(AppFormat.money(fund.currentBalance,in:currency,hidden:hideAmounts)).font(.title2.bold()).monospacedDigit()
            Text("\(currency.name) · fora do total em reais").font(.caption).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(14).frame(maxWidth:.infinity,minHeight:120,alignment:.leading)
        .background { CurrencyBackground(currency:currency,cornerRadius:16) }
        .contentShape(RoundedRectangle(cornerRadius:16)).onTapGesture(perform:edit)
    }

    private var menu:some View {
        CompactActionMenu {
            CompactMenuItem("Editar", action: edit)
            CompactMenuItem("Excluir", role: .destructive, action: delete)
        }
    }
}

struct InvestmentFundEditor:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State var item:InvestmentFund
    @State private var error:String?
    var body:some View {
        BrandForm {
            TextField("Nome",text:$item.name)
            Picker("Tipo",selection:$item.assetType) {
                ForEach(InvestmentAssetType.allCases) { Text($0.rawValue).tag($0) }
            }
            if item.assetType == .currency {
                Picker("Moeda",selection:$item.currency) {
                    ForEach(ForeignCurrency.allCases) { Text("\($0.name) (\($0.symbol))").tag($0) }
                }
            }
            DecimalField(balanceTitle,value:$item.currentBalance)
            if item.foreignCurrency == nil {
                Toggle("Reserva de emergência",isOn:$item.isEmergencyReserve)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            EditorButtons(saveEnabled:canSave,save:save)
        }.editorSheet(item.id == 0 ? "Novo investimento" : "Editar investimento", width:460, saveEnabled:canSave, save:save)
    }
    private var caption:String {
        var text = item.id == 0
            ? "O saldo inicial não é descontado da conta nem conta como aporte do mês."
            : "Alterar o saldo corrige o valor do investimento (rendimentos, cotação) sem registrar aporte ou resgate e sem mexer no saldo da conta."
        if let currency=item.foreignCurrency {
            text += " Informe o valor em \(currency.plural.lowercased()), não em reais. Esse saldo fica separado do total investido e da reserva de emergência."
        } else {
            if item.assetType == .crypto { text += " Informe o valor convertido em reais." }
            if item.isEmergencyReserve { text += " Investimentos marcados como reserva somam no contador de reserva de emergência." }
        }
        return text
    }
    private var balanceTitle:String {
        let title = item.id == 0 ? "Saldo inicial" : "Saldo atual"
        guard let currency=item.foreignCurrency else { return title }
        return "\(title) em \(currency.plural.lowercased()) (\(currency.symbol))"
    }
    private var canSave:Bool { !item.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && item.currentBalance >= 0 }
    private func save() {
        do { try store.save(item); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct InvestmentMovementRow:View {
    @Environment(\.hideAmounts) private var hideAmounts
    let movement:InvestmentMovement
    let fundName:String
    let edit:()->Void
    let delete:()->Void
    var body:some View {
        HStack(spacing:12) {
            Image(systemName:movement.kind == .contribution ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title2).foregroundStyle(movement.kind == .contribution ? .green : .orange)
            VStack(alignment:.leading,spacing:3) {
                Text(movement.kind.rawValue).fontWeight(.medium)
                Text("\(fundName) • \(AppFormat.date.string(from:movement.date))").font(.caption).foregroundStyle(.secondary)
                if !movement.notes.isEmpty { Text(movement.notes).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text("\(movement.kind == .contribution ? "+" : "−") \(AppFormat.money(movement.amount,hidden:hideAmounts))")
                .font(.headline).monospacedDigit().fixedSize()
            CompactActionMenu {
                CompactMenuItem("Editar", action: edit)
                CompactMenuItem("Excluir", role: .destructive, action: delete)
            }
        }
        .padding(.vertical,12).contentShape(Rectangle()).onTapGesture(perform:edit)
    }
}

struct InvestmentMovementEditor:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State var item:InvestmentMovement
    var body:some View {
        BrandForm {
            Picker("Tipo",selection:$item.kind) {
                ForEach(InvestmentMovementKind.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Fundo",selection:$item.fundID) {
                ForEach(store.realFunds) { Text($0.name).tag($0.id) }
            }
            DatePicker("Data",selection:$item.date,displayedComponents:.date)
            DecimalField("Valor",value:$item.amount)
            TextField("Observação (opcional)",text:$item.notes)
            Toggle("Já refletido no saldo da conta",isOn:Binding(get:{!item.balanceApplied},set:{item.balanceApplied = !$0}))
            Text(item.kind == .contribution ? "O aporte será descontado do saldo atual da conta e somado ao fundo." : "O resgate será retirado do fundo e somado ao saldo atual da conta.")
                .font(.caption).foregroundStyle(.secondary)
            EditorButtons(saveEnabled:canSave,save:save)
        }.editorSheet(item.id == 0 ? "Nova movimentação" : "Editar movimentação", width:460, saveEnabled:canSave, save:save)
    }
    private var canSave: Bool { item.amount > 0 && store.realFunds.contains(where:{$0.id == item.fundID}) }
    private func save() { store.save(item);dismiss() }
}

/// Emergency reserve coverage against a six-month goal, filling in when it appears.
private struct ReserveRing: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(AppBrand.accent.opacity(0.14), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(shown, 1))
                .stroke(AngularGradient(colors: [AppBrand.accent.opacity(0.6), AppBrand.accent], center: .center), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: progress >= 1 ? "checkmark.shield.fill" : "shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppBrand.accent)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 44, height: 44)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 1.2, bounce: 0.1).delay(0.3)) { shown = progress }
        }
        .onChange(of: progress) { _, value in withAnimation(.snappy) { shown = value } }
        .accessibilityLabel("Meta de seis meses: \(Int(min(progress, 1) * 100))%")
    }
}

/// The balance held in one foreign currency, kept apart from the totals in reais.
private struct ForeignCurrencyCard:View {
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    let currency:ForeignCurrency
    let count:Int
    let total:Double

    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:10) {
                Text(currency.symbol)
                    .font(.system(size:17,weight:.bold,design:.rounded))
                    .foregroundStyle(currency.deep)
                    .frame(width:32,height:32)
                    .background(currency.highlight,in:Circle())
                VStack(alignment:.leading,spacing:1) {
                    Text("VALOR EM \(currency.plural.uppercased())").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(currency.highlight)
                    Text("Fora do total em reais").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(AppFormat.money(total,in:currency,hidden:hideAmounts))
                .font(.system(size:compact ? 34 : 38,weight:.medium,design:.rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(count == 1 ? "1 investimento" : "\(count) investimentos")
                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background { CurrencyBackground(currency:currency) }
        .accessibilityElement(children:.combine)
    }
}

/// One dot per carousel page; the active one stretches. Tapping a dot jumps to its page.
private struct PageDots:View {
    let pages:[InvestmentPage]
    let active:InvestmentPage
    let select:(InvestmentPage)->Void
    var body:some View {
        HStack(spacing:6) {
            ForEach(pages) { page in
                Button { select(page) } label: {
                    Capsule()
                        .fill(page == active ? page.tint : Color.secondary.opacity(0.3))
                        .frame(width:page == active ? 18 : 7,height:7)
                        .padding(.vertical,6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor()
                .accessibilityLabel(page.accessibilityName)
                .accessibilityAddTraits(page == active ? .isSelected : [])
            }
        }
        .frame(maxWidth:.infinity)
    }
}

private enum InvestmentPage:Hashable,Identifiable {
    case reais
    case foreign(ForeignCurrency)
    var id:Self { self }

    var listTitle:String {
        switch self {
        case .reais: "Seus investimentos"
        case .foreign(let currency): "Seus investimentos em \(currency.plural.lowercased())"
        }
    }
    var accessibilityName:String {
        switch self {
        case .reais: "Reais"
        case .foreign(let currency): currency.plural
        }
    }
    var tint:Color {
        switch self {
        case .reais: AppBrand.accent
        case .foreign(let currency): currency.base
        }
    }
}

/// Deep blue with a faint ring of twelve gold stars for the euro.
private struct CurrencyBackground:View {
    let currency:ForeignCurrency
    var cornerRadius:CGFloat = 22

    var body:some View {
        let shape=RoundedRectangle(cornerRadius:cornerRadius,style:.continuous)
        ZStack {
            LinearGradient(colors:[currency.deep,currency.base],startPoint:.topLeading,endPoint:.bottomTrailing)
            RadialGradient(colors:[.white.opacity(0.14),.clear],center:.topTrailing,startRadius:0,endRadius:220)
            StarRing(color:currency.highlight.opacity(0.22))
                .frame(width:150,height:150)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing)
                .offset(x:40,y:-34)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.1)))
    }
}

private struct StarRing:View {
    let color:Color
    var body:some View {
        GeometryReader { geometry in
            let radius=min(geometry.size.width,geometry.size.height) / 2 - 10
            ForEach(0..<12,id:\.self) { index in
                let angle=Double(index) / 12 * 2 * .pi
                Image(systemName:"star.fill")
                    .font(.system(size:13))
                    .foregroundStyle(color)
                    .position(x:geometry.size.width / 2 + radius * sin(angle),y:geometry.size.height / 2 - radius * cos(angle))
            }
        }
        .accessibilityHidden(true)
    }
}

private extension ForeignCurrency {
    var deep:Color {
        switch self {
        case .euro: Color(red:0.02,green:0.11,blue:0.36)
        }
    }
    var base:Color {
        switch self {
        case .euro: Color(red:0.0,green:0.24,blue:0.62)
        }
    }
    var highlight:Color {
        switch self {
        case .euro: Color(red:1.0,green:0.8,blue:0.0)
        }
    }
}
