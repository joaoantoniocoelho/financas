import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

private struct CompactLayoutKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True on iPhone-width layouts. The Mac window always uses the regular layout.
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

extension View {
    /// Mac editors are fixed-width sheets with their buttons at the bottom of the form.
    /// On iOS they are half-height green bottom sheets with Cancel and Save in the sheet's bar,
    /// so the actions stay visible at the medium detent.
    func editorSheet(
        _ title: String, width: CGFloat, saveTitle: String = "Salvar", saveEnabled: Bool = true,
        save: (() -> Void)? = nil
    ) -> some View {
        modifier(EditorSheet(title: title, width: width, saveTitle: saveTitle, saveEnabled: saveEnabled, save: save))
    }
}

private struct EditorSheet: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let width: CGFloat
    let saveTitle: String
    let saveEnabled: Bool
    let save: (() -> Void)?

    func body(content: Content) -> some View {
        #if os(macOS)
            content.padding().frame(width: width).navigationTitle(title)
        #else
            NavigationStack {
                content
                    .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(save == nil ? "Fechar" : "Cancelar") { dismiss() }
                        }
                        if let save {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(saveTitle, action: save).fontWeight(.semibold).disabled(!saveEnabled)
                            }
                        }
                    }
            }
            .editorChrome()
            .presentationDetents([.medium, .large])
        #endif
    }
}

#if os(iOS)
    extension View {
        /// The green, dark-scheme bottom sheet look.
        func editorChrome() -> some View {
            tint(AppBrand.mint)
                .environment(\.colorScheme, .dark)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground { SheetBackground() }
        }
    }

#endif

/// A `Form` whose rows sit on the green sheet as translucent cards on iOS; a plain `Form` on the Mac.
struct BrandForm<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(iOS)
            Form { Group(content: content).listRowBackground(Color.white.opacity(0.08)) }
        #else
            Form(content: content)
        #endif
    }
}

#if os(iOS)
    private struct SheetBackground: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.03, green: 0.24, blue: 0.17), Color(red: 0.015, green: 0.13, blue: 0.095)],
                    startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [AppBrand.mint.opacity(0.14), .clear], center: .topLeading, startRadius: 0, endRadius: 380)
            }
        }
    }
#endif

/// Number input for money. On iOS the text is parsed while typing, so a value is never lost
/// when the user taps Save without dismissing the decimal keypad.
struct DecimalField: View {
    let title: String
    @Binding var value: Double
    init(_ title: String, value: Binding<Double>) { self.title = title; _value = value }

    #if os(macOS)
        var body: some View { TextField(title, value: $value, format: .number) }
    #else
        @State private var text = ""
        var body: some View {
            LabeledContent(title) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onAppear { text = value == 0 ? "" : NumberInput.string(from: value) }
                    .onChange(of: text) { _, newValue in value = NumberInput.double(from: newValue) ?? 0 }
            }
        }
    #endif
}

/// Optional whole-number input, such as a day of the month.
struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?
    init(_ title: String, value: Binding<Int?>) { self.title = title; _value = value }

    #if os(macOS)
        var body: some View { TextField(title, value: $value, format: .number) }
    #else
        @State private var text = ""
        var body: some View {
            LabeledContent(title) {
                TextField("—", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .onAppear { text = value.map(String.init) ?? "" }
                    .onChange(of: text) { _, newValue in value = Int(newValue.filter(\.isNumber)) }
            }
        }
    #endif
}

#if os(iOS)
    enum NumberInput {
        private static let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        static func string(from value: Double) -> String { formatter.string(from: value as NSNumber) ?? "" }

        static func double(from text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let number = formatter.number(from: trimmed) { return number.doubleValue }
            // Accept either separator, whatever the keypad offers.
            return Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }
    }
#endif

// MARK: - iPhone building blocks

/// Title on the left, round actions on the right: the phone counterpart of `ScreenHeader`.
struct MobileHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 30, weight: .medium, design: .serif)).lineLimit(1).minimumScaleFactor(
                    0.8)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) { actions }
        }
        .padding(.leading, 2)
    }
}

/// A 44 pt round button. Prominent is mint, like the dashboard's edit button; secondary is a soft green tint.
struct CircleActionLabel: View {
    let systemImage: String
    var prominent = true
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(prominent ? AppBrand.forest : AppBrand.accent)
            .background(prominent ? AppBrand.mint : AppBrand.accent.opacity(0.14), in: Circle())
            .contentShape(Circle())
    }
}

struct CircleActionButton: View {
    let title: String
    let systemImage: String
    var prominent = true
    let action: () -> Void
    var body: some View {
        Button(action: action) { CircleActionLabel(systemImage: systemImage, prominent: prominent) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
    }
}

/// Horizontally scrolling filter chips.
struct ChipPicker<Value: Hashable & Identifiable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @Namespace private var chip

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option }
                    } label: {
                        Text(title(option))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background {
                                // The selected fill slides between chips.
                                if selected {
                                    Capsule().fill(AppBrand.evergreen).matchedGeometryEffect(id: "chip", in: chip)
                                } else {
                                    Capsule().fill(Color.primary.opacity(0.06))
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.selection, trigger: selection)
        // Scroll edge to edge, past the screen's 16 pt margin.
        .padding(.horizontal, -16)
    }
}

/// A titled group of rows in one rounded card, used instead of `List` sections on iPhone.
struct CompactCardSection<Item: Identifiable, Row: View>: View {
    let title: String
    var total: String?
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let total { Text(total).font(.caption).monospacedDigit() }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .brandSurface(cornerRadius: 18)
            }
        }
    }
}
