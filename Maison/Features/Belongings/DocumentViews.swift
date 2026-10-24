import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

// MARK: - Rows and preview

struct DocumentRow: View {
    @Environment(BelongingsStore.self) private var belongings
    let document: HomeDocument
    var showsItem = false

    var body: some View {
        SettingsRow(title: LocalizedStringKey(stringLiteral: title), detail: detail, value: amount, showsChevron: true) {
            SettingsIcon(symbol: document.type.symbol, color: .indigo)
        }
    }

    private var title: String {
        document.merchant ?? document.extraction.product ?? String(localized: document.type.titleResource)
    }

    private var detail: String? {
        var parts: [String] = []
        if let date = document.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        if showsItem, let item = belongings.item(document.itemID) { parts.append(item.emoji + " " + item.name) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var amount: String? {
        document.amount.map { Money.text($0, currency: document.currency) }
    }
}

extension DocumentType {
    /// The same titles as `title`, for places that need a String.
    var titleResource: LocalizedStringResource {
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
}

/// The document itself, as it was scanned.
struct DocumentPreview: View {
    @Environment(BelongingsStore.self) private var belongings
    @Environment(\.dismiss) private var dismiss
    let document: HomeDocument
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            Group {
                if let url = belongings.fileURL(of: document), FileManager.default.fileExists(atPath: url.path()) {
                    PDFView.Representable(url: url)
                } else {
                    ContentUnavailableView("File Not Found", systemImage: "doc.questionmark",
                                           description: Text("The details read on it are still kept."))
                }
            }
            .background(Theme.background)
            .navigationTitle(document.merchant ?? String(localized: document.type.titleResource))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Object", systemImage: "link") { isPicking = true }
                }
                if let url = belongings.fileURL(of: document) {
                    ToolbarItem(placement: .bottomBar) {
                        ShareLink(item: url)
                    }
                }
            }
            .sheet(isPresented: $isPicking) {
                ItemPicker(selection: document.itemID) { belongings.attach(document, to: $0) }
            }
        }
    }
}

private extension PDFView {
    struct Representable: UIViewRepresentable {
        let url: URL

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.backgroundColor = .clear
            view.document = PDFDocument(url: url)
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {}
    }
}

/// Chooses the object a document is about, or none.
struct ItemPicker: View {
    @Environment(BelongingsStore.self) private var belongings
    @Environment(\.dismiss) private var dismiss
    let selection: UUID?
    let choose: (Item?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button { choose(nil); dismiss() } label: {
                    HStack {
                        Text("No Object").foregroundStyle(.primary)
                        Spacer()
                        if selection == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                ForEach(belongings.items) { item in
                    Button { choose(item); dismiss() } label: {
                        HStack(spacing: 12) {
                            EmojiTile(emoji: item.emoji, size: 32)
                            Text(item.name).foregroundStyle(.primary)
                            Spacer()
                            if selection == item.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            }
            .navigationTitle("Which Object?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Documents page

/// Every document kept, by type and by object. Reached from Settings.
struct DocumentsPage: View {
    @Environment(BelongingsStore.self) private var belongings
    @State private var type: TypeFilter = .all
    @State private var itemID: UUID?
    @State private var opened: HomeDocument?
    @State private var isScanning = false

    enum TypeFilter: Hashable {
        case all
        case type(DocumentType)
    }

    var body: some View {
        let shown = belongings.documents.filter { document in
            (type == .all || type == .type(document.type)) && (itemID == nil || document.itemID == itemID)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if belongings.documents.isEmpty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("Scan a bill, a contract or a manual. Apple Intelligence reads it on this iPhone and files it.")
                    } actions: {
                        Button("Scan a Document") { isScanning = true }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(.top, 40)
                } else {
                    filters
                    if shown.isEmpty {
                        Text("No document matches these filters.")
                            .font(.roundedSubheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        SettingsGroup {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, document in
                                if index > 0 { SettingsDivider() }
                                Button { opened = document } label: { DocumentRow(document: document, showsItem: itemID == nil) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scan", systemImage: "doc.viewfinder") { Haptics.impact(); isScanning = true }
            }
        }
        .sheet(item: $opened) { DocumentPreview(document: $0) }
        .fullScreenCover(isPresented: $isScanning) { DocumentScanFlow(target: nil) }
    }

    private var filters: some View {
        let types = DocumentType.allCases.filter { type in belongings.documents.contains { $0.type == type } }
        return HStack(spacing: 8) {
            PillPicker(options: [(TypeFilter.all, "All", nil)] + types.map { (TypeFilter.type($0), $0.title, nil) }, selection: $type)
            Menu {
                Picker("Object", selection: $itemID) {
                    Text("Every Object").tag(UUID?.none)
                    ForEach(belongings.items) { Text($0.emoji + " " + $0.name).tag(Optional($0.id)) }
                }
            } label: {
                Image(systemName: itemID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Filter by Object")
        }
    }
}

// MARK: - Scan

/// Scans a document and reads it on the iPhone. From an object's sheet (`target`), the document is that
/// object's; from elsewhere, Maison recognises the object or proposes to create it.
struct DocumentScanFlow: View {
    @Environment(\.dismiss) private var dismiss
    let target: Item?

    @State private var step: Step = .capture
    @State private var pages: [UIImage] = []
    @State private var photo: PhotosPickerItem?
    @State private var isImporting = false

    enum Step: Equatable {
        case capture
        case reading
        case review(DocumentReading)
    }

    var body: some View {
        switch step {
        case .capture:
            if VNDocumentCameraViewController.isSupported, !ProcessInfo.processInfo.arguments.contains("-noCamera") {
                DocumentCamera { scanned in
                    if scanned.isEmpty { dismiss() } else { read(scanned) }
                }
                .ignoresSafeArea()
            } else {
                chooser
            }
        case .reading:
            ReadingView()
        case .review(let reading):
            DocumentReview(target: target, reading: reading, pages: pages)
        }
    }

    /// Without a camera: a photo or a file, so scanning is never a dead end.
    private var chooser: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Choose the document")
                    .font(.roundedTitle3)
                Text("A photo of it, or a PDF from Files.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                PhotosPicker(selection: $photo, matching: .images) {
                    Text("Choose a Photo").font(.roundedHeadline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                WideButton(title: "Choose a File", style: .secondary) { isImporting = true }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 16)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        read([image])
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf, .image]) { result in
                guard case .success(let url) = result else { return }
                importFile(url)
            }
        }
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let image = UIImage(contentsOfFile: url.path()) {
            read([image])
        } else if let pdf = PDFDocument(url: url) {
            let images = (0..<min(pdf.pageCount, 5)).compactMap { index -> UIImage? in
                guard let page = pdf.page(at: index) else { return nil }
                return page.thumbnail(of: page.bounds(for: .mediaBox).size.applying(.init(scaleX: 2, y: 2)), for: .mediaBox)
            }
            read(images, pdfText: pdf.string)
        }
    }

    private func read(_ scanned: [UIImage], pdfText: String? = nil) {
        pages = scanned
        withAnimation(.smooth) { step = .reading }
        Task {
            var text = pdfText ?? ""
            if text.count < 40 {
                text = (try? await DocumentReader.text(of: scanned.compactMap(\.cgImage))) ?? ""
            }
            let reading = await DocumentReader.read(text)
            withAnimation(.smooth) { step = .review(reading) }
        }
    }
}

/// The system document scanner.
private struct DocumentCamera: UIViewControllerRepresentable {
    let done: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            done([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            done([])
        }
    }
}

/// While the iPhone reads the document.
private struct ReadingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.generated)
                .symbolEffect(.pulse, options: .repeating, isActive: isAnimating)
            Text("Reading the document")
                .font(.roundedTitle3)
            Text(Intelligence.isAvailable ? "Apple Intelligence reads it on this iPhone. Nothing is sent anywhere."
                                          : "Maison looks for its date. You fill in the rest.")
                .font(.roundedSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Review

/// What was read, checked by the code, then which object it is about.
private struct DocumentReview: View {
    @Environment(BelongingsStore.self) private var belongings
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: Item?
    @State var reading: DocumentReading
    let pages: [UIImage]

    /// The object the household confirmed, or nil while it's being chosen.
    @State private var chosen: Item?
    @State private var isPicking = false
    @State private var keptTaps = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    readValues
                    if let target {
                        prefill(for: target)
                    } else {
                        attachment
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                WideButton(title: "Keep the Document") { keep() }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 8)
            }
            .sheet(isPresented: $isPicking) {
                ItemPicker(selection: chosen?.id) { chosen = $0 }
            }
            .sensoryFeedback(.success, trigger: keptTaps)
            .errorFeedback(belongings.lastError)
        }
    }

    private var readValues: some View {
        let extraction = reading.extraction
        return SettingsGroup("Read on the Document") {
            HStack {
                Text("Type").font(.roundedBody)
                Spacer()
                Picker("Type", selection: $reading.extraction.type) {
                    ForEach(DocumentType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .tint(.secondary)
            }
            .padding(.vertical, 4)
            value("From", extraction.merchant)
            value("Date", extraction.date?.formatted(date: .abbreviated, time: .omitted))
            value("Amount", extraction.amount.map { Money.text($0, currency: extraction.currency) })
            value("About", extraction.product)
            if !reading.rejected.isEmpty {
                Theme.separator.frame(height: 1)
                Label("Some values didn’t match the text of the document and were left out. Enter them on the object if you need them.",
                      systemImage: "exclamationmark.magnifyingglass")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func value(_ title: LocalizedStringKey, _ text: String?) -> some View {
        if let text {
            Theme.separator.frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.roundedBody)
                Spacer(minLength: 12)
                Text(text)
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: Case A: from an object

    private func prefill(for item: Item) -> some View {
        let result = ItemPrefill.apply(reading.extraction, to: item)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                EmojiTile(emoji: item.emoji)
                Text(item.name).font(.roundedHeadline)
            }
            if !result.filled.isEmpty {
                Text("Fills in \(result.filled.map(\.title).formatted(.list(type: .and))).")
                    .font(.roundedSubheadline)
            }
            ForEach(result.conflicts, id: \.field) { conflict in
                Text("\(conflict.field.title): keeps \(conflict.current), the document says \(conflict.proposed).")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
            if result.filled.isEmpty, result.conflicts.isEmpty {
                Text("Nothing new for this object: the document is kept with it.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Case B: from elsewhere

    @ViewBuilder
    private var attachment: some View {
        if let chosen {
            chosenCard(chosen)
        } else {
            switch ItemMatcher.match(reading.extraction, among: belongings.items) {
            case .one(let item):
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        EmojiTile(emoji: item.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.roundedHeadline)
                            Text("Recognised").font(.roundedFootnote).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        WideButton(title: "Confirm") { chosen = item }
                        WideButton(title: "Change", style: .secondary) { isPicking = true }
                    }
                }
                .padding(16)
                .cardStyle()
            case .several(let candidates):
                SettingsGroup("Which Object Is It About?") {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SettingsDivider() }
                        Button { chosen = item } label: {
                            SettingsRow(title: LocalizedStringKey(stringLiteral: item.name), detail: item.brand?.value) {
                                EmojiTile(emoji: item.emoji, size: 30)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    SettingsDivider()
                    Button { isPicking = true } label: {
                        SettingsRow(symbol: "ellipsis", color: .gray, title: "Another Object")
                    }
                    .buttonStyle(.plain)
                }
                newItemCard
            case .none:
                newItemCard
            }
        }
    }

    @ViewBuilder
    private var newItemCard: some View {
        if let product = reading.extraction.product {
            let emoji = reading.emoji ?? reading.kind.defaultEmoji
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    EmojiTile(emoji: emoji)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(product).font(.roundedHeadline)
                        Text("Not among your objects yet").font(.roundedFootnote).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    WideButton(title: "Create It") { chosen = newItem(named: product, emoji: emoji) }
                    WideButton(title: "Choose", style: .secondary) { isPicking = true }
                }
            }
            .padding(16)
            .cardStyle()
        } else {
            WideButton(title: "Attach to an Object", style: .secondary) { isPicking = true }
        }
    }

    private func chosenCard(_ item: Item) -> some View {
        HStack(spacing: 12) {
            EmojiTile(emoji: item.emoji)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.roundedHeadline)
                Text(belongings.item(item.id) == nil ? "Will be created" : "The document goes with it")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change") { chosen = nil }
                .font(.roundedSubheadline)
        }
        .padding(16)
        .cardStyle()
    }

    private func newItem(named name: String, emoji: String) -> Item {
        let hint = reading.extraction.roomHint.map(ItemMatcher.normalized)
        let room = hint.flatMap { hint in store.rooms.first { ItemMatcher.normalized($0.name) == hint } }
        return Item(name: name, emoji: emoji, kind: reading.kind, category: reading.category, roomID: room?.id)
    }

    // MARK: Keeping

    private func keep() {
        let item = target ?? chosen
        if let item {
            let result = ItemPrefill.apply(reading.extraction, to: item)
            belongings.save(result.item)
        }
        guard belongings.keep(reading, pages: pages, for: item) != nil else { return }
        keptTaps += 1
        dismiss()
    }
}

extension ItemPrefill.Field {
    var title: String {
        switch self {
        case .purchasePrice: String(localized: "the price")
        case .purchaseDate: String(localized: "the purchase date")
        case .warrantyEnd: String(localized: "the warranty")
        case .brand: String(localized: "the brand")
        case .model: String(localized: "the model")
        }
    }
}
