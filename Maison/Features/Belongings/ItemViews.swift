import SwiftUI

// MARK: - Small pieces

/// An object's emoji on a soft tile: objects get emojis, the rest of the app SF Symbols.
struct EmojiTile: View {
    let emoji: String
    var size: CGFloat = 40

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Theme.pill, in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Where a value comes from, next to it.
struct OriginLabel: View {
    let origin: ValueOrigin

    var body: some View {
        Label(origin.title, systemImage: origin.symbol)
            .labelStyle(.titleAndIcon)
            .font(.roundedFootnote)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

extension ValueOrigin {
    var title: LocalizedStringKey {
        switch self {
        case .measured: "Measured"
        case .estimated: "Estimated"
        case .entered: "Entered"
        }
    }

    var symbol: String {
        switch self {
        case .measured: "gauge.with.dots.needle.67percent"
        case .estimated: "function"
        case .entered: "pencil"
        }
    }
}

extension ConsumableCategory {
    var title: LocalizedStringKey {
        switch self {
        case .razorBlades: "Razor blades"
        case .airConditionerFilter: "Air conditioner filter"
        case .ventilationFilter: "Ventilation filter"
        case .waterFilter: "Water filter"
        case .vacuumBags: "Vacuum bags"
        case .lightBulb: "Light bulb"
        case .laundryDetergent: "Laundry detergent"
        case .dishwasherTablets: "Dishwasher tablets"
        case .smokeDetectorBattery: "Smoke detector battery"
        }
    }
}

extension DocumentType {
    var title: LocalizedStringKey {
        switch self {
        case .invoice: "Invoice"
        case .receipt: "Receipt"
        case .contract: "Contract"
        case .warranty: "Warranty"
        case .manual: "Manual"
        case .quote: "Quote"
        case .lease: "Lease"
        case .insurance: "Insurance"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .invoice, .receipt: "doc.text.fill"
        case .contract, .lease: "signature"
        case .warranty: "checkmark.shield.fill"
        case .manual: "book.closed.fill"
        case .quote: "doc.badge.ellipsis"
        case .insurance: "umbrella.fill"
        case .other: "doc.fill"
        }
    }
}

enum Money {
    static func text(_ amount: Decimal, currency: String?) -> String {
        amount.formatted(.currency(code: currency ?? Locale.current.currency?.identifier ?? "EUR"))
    }
}

/// One object in a list: its emoji, its name, and what matters next about it.
struct ItemRow: View {
    @Environment(BelongingsStore.self) private var belongings
    let item: Item
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                EmojiTile(emoji: item.emoji)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.roundedHeadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.roundedFootnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(radius: Theme.rowRadius)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }

    /// The nearest replacement among its consumables, otherwise its brand.
    private var detail: String? {
        let next = ([item] + belongings.consumables(of: item))
            .compactMap { belongings.schedule(of: $0)?.next }
            .min()
        if let next {
            return String(localized: "Replace \(next.formatted(.relative(presentation: .named)))")
        }
        return item.brand?.value
    }
}

/// The objects of a room, under its devices, with a way to add one.
struct RoomItemsSection: View {
    @Environment(BelongingsStore.self) private var belongings
    let room: Area
    @State private var opened: Item?
    @State private var isAdding = false

    var body: some View {
        let items = belongings.items(in: room.id)
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Objects", actionTitle: "Add") { isAdding = true }
            if items.isEmpty {
                Text("Things that aren’t connected, like a sofa or a razor, with their bills and what they need replacing.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(items) { item in
                ItemRow(item: item) { opened = item }
            }
        }
        .sheet(item: $opened) { ItemSheet(itemID: $0.id) }
        .sheet(isPresented: $isAdding) {
            ItemEditor(item: Item(name: "", roomID: room.id))
        }
    }
}

// MARK: - Object sheet

/// One object: what is known about it and where each value comes from, its consumables and its documents.
struct ItemSheet: View {
    @Environment(BelongingsStore.self) private var belongings
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    @State private var isEditing = false
    @State private var isScanning = false
    @State private var openedDocument: HomeDocument?

    var body: some View {
        NavigationStack {
            Group {
                if let item = belongings.item(itemID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                            header(item)
                            if item.kind == .consumable {
                                ConsumableSection(item: item)
                            }
                            details(item)
                            let consumables = belongings.consumables(of: item)
                            if !consumables.isEmpty {
                                SettingsGroup("To Replace") {
                                    ForEach(Array(consumables.enumerated()), id: \.element.id) { index, consumable in
                                        if index > 0 { SettingsDivider() }
                                        NavigationLink { ConsumablePage(itemID: consumable.id) } label: {
                                            SettingsRow(title: LocalizedStringKey(stringLiteral: consumable.name),
                                                        detail: nextText(consumable), showsChevron: true) {
                                                EmojiTile(emoji: consumable.emoji, size: 30)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            documents(item)
                            WideButton(title: "Scan a Document", style: .secondary) {
                                Haptics.impact()
                                isScanning = true
                            }
                            .padding(.top, 6)
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.bottom, 24)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Edit") { isEditing = true }
                        }
                    }
                    .sheet(isPresented: $isEditing) { ItemEditor(item: item) }
                    .fullScreenCover(isPresented: $isScanning) { DocumentScanFlow(target: item) }
                    .sheet(item: $openedDocument) { DocumentPreview(document: $0) }
                } else {
                    ContentUnavailableView("Object Removed", systemImage: "shippingbox")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.background)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func header(_ item: Item) -> some View {
        HStack(spacing: 14) {
            EmojiTile(emoji: item.emoji, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text(item.kind == .consumable ? "Bought again and again" : "Kept for years")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func details(_ item: Item) -> some View {
        let candidates: [(LocalizedStringKey, String, ValueOrigin)?] = [
            item.brand.map { ("Brand", $0.value, $0.origin) },
            item.model.map { ("Model", $0.value, $0.origin) },
            item.purchasePrice.map { ("Price", Money.text($0.value, currency: item.currency), $0.origin) },
            item.purchaseDate.map { ("Bought", $0.value.formatted(date: .abbreviated, time: .omitted), $0.origin) },
            item.warrantyEnd.map { ("Warranty Until", $0.value.formatted(date: .abbreviated, time: .omitted), $0.origin) },
        ]
        let rows = candidates.compactMap(\.self)
        if rows.isEmpty {
            Text("Scan its bill and Maison fills in the price, the date and the warranty.")
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        } else {
            SettingsGroup("Details") {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Theme.separator.frame(height: 1) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.0).font(.roundedBody)
                            OriginLabel(origin: row.2)
                        }
                        Spacer(minLength: 8)
                        Text(row.1)
                            .font(.roundedSubheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private func documents(_ item: Item) -> some View {
        let documents = belongings.documents(of: item)
        if !documents.isEmpty {
            SettingsGroup("Documents") {
                ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                    if index > 0 { SettingsDivider() }
                    Button { openedDocument = document } label: { DocumentRow(document: document) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func nextText(_ consumable: Item) -> String? {
        guard let next = belongings.schedule(of: consumable)?.next else { return nil }
        return String(localized: "Replace \(next.formatted(.relative(presentation: .named)))")
    }
}

// MARK: - Consumable

/// A consumable's own page, from its durable's sheet.
struct ConsumablePage: View {
    @Environment(BelongingsStore.self) private var belongings
    let itemID: UUID

    var body: some View {
        ScrollView {
            if let item = belongings.item(itemID) {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    HStack(spacing: 14) {
                        EmojiTile(emoji: item.emoji, size: 52)
                        if let category = item.category {
                            Text(category.title)
                                .font(.roundedSubheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    ConsumableSection(item: item)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .navigationTitle(belongings.item(itemID)?.name ?? "")
    }
}

/// When it will need replacing and why, its history, and the button to log a replacement.
struct ConsumableSection: View {
    @Environment(BelongingsStore.self) private var belongings
    let item: Item
    @State private var replacedTaps = 0

    var body: some View {
        let schedule = belongings.schedule(of: item)
        let history = belongings.replacements(of: item)
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Next Replacement", systemImage: "arrow.triangle.2.circlepath")
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.teal)
                if let next = schedule?.next {
                    Text(next.formatted(.dateTime.day().month(.wide)))
                        .font(NumberSize.medium.value)
                    Text(next.formatted(.relative(presentation: .named)))
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap Replaced the next time you change it, and Maison learns how long it lasts.")
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                }
                if let schedule {
                    HStack(spacing: 6) {
                        Text(basisText(schedule))
                            .font(.roundedFootnote)
                            .foregroundStyle(.secondary)
                        OriginLabel(origin: schedule.origin)
                    }
                }
                WideButton(title: "Replaced Today") {
                    replacedTaps += 1
                    belongings.markReplaced(item)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .cardStyle()
            .sensoryFeedback(.success, trigger: replacedTaps)

            if !history.isEmpty {
                SettingsGroup("History") {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Theme.separator.frame(height: 1) }
                        HStack {
                            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.roundedBody)
                            Spacer()
                            Label(event.source == .document ? "From a document" : "Tapped",
                                  systemImage: event.source == .document ? "doc.text" : "hand.tap")
                                .font(.roundedFootnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func basisText(_ schedule: ReplacementSchedule) -> String {
        switch schedule.basis {
        case .typical:
            String(localized: "Every \(schedule.intervalDays) days, usual for this kind")
        case .history(let count):
            String(localized: "Every \(schedule.intervalDays) days, from your \(count) replacements")
        }
    }
}

// MARK: - Editor

/// Creates or edits an object. Only the name is required.
struct ItemEditor: View {
    @Environment(BelongingsStore.self) private var belongings
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var item: Item
    @State private var priceText = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date.now
    @State private var isConfirmingDelete = false

    private var isNew: Bool { belongings.item(item.id) == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("📦", text: emojiBinding)
                            .font(.system(size: 28))
                            .multilineTextAlignment(.center)
                            .frame(width: 52, height: 52)
                            .background(Theme.pill, in: .rect(cornerRadius: 16))
                            .accessibilityLabel("Emoji")
                        TextField("Name", text: $item.name)
                            .font(.roundedHeadline)
                    }
                    Picker("Kind", selection: $item.kind) {
                        Text("Kept for years").tag(ItemKind.durable)
                        Text("Bought again and again").tag(ItemKind.consumable)
                    }
                    if item.kind == .consumable {
                        Picker("Category", selection: $item.category) {
                            Text("Other").tag(ConsumableCategory?.none)
                            ForEach(ConsumableCategory.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                    }
                    Picker("Room", selection: $item.roomID) {
                        Text("None").tag(String?.none)
                        ForEach(store.rooms) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    TextField("Brand", text: sourcedText(\.brand))
                    TextField("Model", text: sourcedText(\.model))
                    TextField("Price", text: $priceText)
                        .keyboardType(.decimalPad)
                    Toggle("Purchase Date", isOn: $hasPurchaseDate.animation())
                    if hasPurchaseDate {
                        DatePicker("Bought", selection: $purchaseDate, in: ...Date.now, displayedComponents: .date)
                    }
                } footer: {
                    Text("Scanning the bill fills these in for you.")
                }
                if !isNew {
                    Section {
                        Button("Delete Object", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Object" : "Edit Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this object, its consumables’ history and links to its documents?",
                                isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Object", role: .destructive) {
                    belongings.delete(item)
                    dismiss()
                }
            }
            .onAppear {
                priceText = item.purchasePrice.map { NSDecimalNumber(decimal: $0.value).stringValue } ?? ""
                hasPurchaseDate = item.purchaseDate != nil
                purchaseDate = item.purchaseDate?.value ?? .now
            }
        }
    }

    private var emojiBinding: Binding<String> {
        Binding {
            item.emoji
        } set: { text in
            // Keeps the last emoji typed; anything else goes back to the kind's default.
            item.emoji = text.last.map(String.init).flatMap(DocumentText.singleEmoji) ?? item.kind.defaultEmoji
        }
    }

    private func sourcedText(_ keyPath: WritableKeyPath<Item, Sourced<String>?>) -> Binding<String> {
        Binding {
            item[keyPath: keyPath]?.value ?? ""
        } set: { text in
            let text = text.trimmingCharacters(in: .whitespaces)
            if text == item[keyPath: keyPath]?.value { return }
            item[keyPath: keyPath] = text.isEmpty ? nil : Sourced(value: text, origin: .entered)
        }
    }

    private func save() {
        item.name = item.name.trimmingCharacters(in: .whitespaces)
        if item.kind == .durable { item.category = nil }
        if item.emoji == ItemKind.durable.defaultEmoji || item.emoji == ItemKind.consumable.defaultEmoji {
            item.emoji = item.kind.defaultEmoji
        }
        let price = Decimal(string: priceText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
        if price != item.purchasePrice?.value {
            item.purchasePrice = price.map { Sourced(value: $0, origin: .entered) }
        }
        if !hasPurchaseDate {
            item.purchaseDate = nil
        } else if purchaseDate != item.purchaseDate?.value {
            item.purchaseDate = Sourced(value: purchaseDate, origin: .entered)
        }
        belongings.save(item)
        Haptics.success()
        dismiss()
    }
}
