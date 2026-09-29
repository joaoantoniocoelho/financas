import SwiftUI

struct InvestmentsView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    @State private var editing:InvestmentMovement?
    private let columns=[GridItem(.adaptive(minimum:230),spacing:12)]

    var body:some View {
        if let month=store.selectedMonth {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if compact {
                        MobileHeader(title: "Investimentos", subtitle: "Fundos, aportes e resgates") {
                            CircleActionButton(title: "Nova movimentação", systemImage: "plus") { newMovement(month) }
                        }
                        .entrance(0)
                    } else {
                        ScreenHeader("Investimentos",subtitle:"Acompanhe seus fundos, aportes e resgates",inset:0) {
                            Button { newMovement(month) } label:{ Label("Nova movimentação",systemImage:"plus") }
                        }
                    }

                    if compact {
                        heroCard.entrance(1)
                    } else {
                        LazyVGrid(columns:columns,spacing:12) {
                            MetricCard("Valor atual investido",store.totalInvested,"chart.line.uptrend.xyaxis",color:.green,size:.featured)
                            MetricCard("Meta do mês",store.totals.investmentsPlanned,"target",size:.featured)
                            MetricCard("Aportado no mês",store.totals.investmentsActual,"arrow.up.circle",color:.green,size:.featured)
                        }
                    }

                    EmergencyReserveCard(fund:store.emergencyReserve,fixedExpenses:store.monthlyFixedExpenseBaseline,months:store.emergencyReserveMonths)
                        .entrance(2)

                    GroupBox("Fundos e objetivos") {
                        LazyVGrid(columns:columns,spacing:12) {
                            ForEach(store.investmentFunds) { fund in FundCard(fund:fund) }
                        }.padding(compact ? 0 : 6)
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
            }.sheet(item:$editing) { InvestmentMovementEditor(item:$0) }
        } else { EmptyMonthView() }
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
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroBackground() }
    }

    private func newMovement(_ month: BudgetMonth) {
        guard let fund=store.investmentFunds.first else { return }
        editing=InvestmentMovement(id:0,monthID:month.id,fundID:fund.id,date:.now,kind:.contribution,amount:0,notes:"")
    }
}

private struct EmergencyReserveCard:View {
    @Environment(\.hideAmounts) private var hideAmounts
    @Environment(\.compactLayout) private var compact
    let fund:InvestmentFund?
    let fixedExpenses:Double
    let months:Double
    var body:some View {
        GroupBox {
            AdaptiveStack(vertical: compact, spacing: compact ? 12 : 18) {
                HStack(spacing:compact ? 12 : 18) {
                    ReserveRing(progress: fixedExpenses > 0 ? months / 6 : 0)
                    VStack(alignment:.leading,spacing:4) {
                        Text("Reserva de emergência").font(.headline)
                        Text(fund?.name ?? "Nenhum fundo definido").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !compact { Spacer() }
                VStack(alignment:compact ? .leading : .trailing,spacing:4) {
                    Text(fixedExpenses > 0 ? "\(months.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR")))) meses" : "—").font(.title.bold()).monospacedDigit()
                    if let fund {
                        Text("\(AppFormat.money(fund.currentBalance,hidden:hideAmounts)) ÷ \(AppFormat.money(fixedExpenses,hidden:hideAmounts)) em gastos fixos mensais")
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
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top) {
                Image(systemName:fund.isEmergencyReserve ? "shield.fill" : (fund.countsAsInvestment ? "building.columns.fill" : "airplane.departure"))
                    .foregroundStyle(fund.isEmergencyReserve ? .green : .accentColor)
                Text(fund.name).font(.headline).lineLimit(2)
                Spacer()
            }
            Text(AppFormat.money(fund.currentBalance,hidden:hideAmounts)).font(.title2.bold()).monospacedDigit()
            Text(fund.isEmergencyReserve ? "Reserva de emergência" : (fund.countsAsInvestment ? "Fundo de investimento" : "Objetivo financeiro"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth:.infinity,minHeight:120,alignment:.leading)
        .background(AppBrand.canvas,in:RoundedRectangle(cornerRadius:16))
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
                ForEach(store.investmentFunds) { Text($0.name).tag($0.id) }
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
    private var canSave: Bool { item.amount > 0 && store.investmentFunds.contains(where:{$0.id == item.fundID}) }
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
