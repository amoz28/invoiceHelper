import SwiftUI

/// The conversational flow: the app asks, the user answers, repeat until saved.
///
/// The view owns the wiring between the session controller, the parser, and the
/// dialogue manager, and holds no invoice logic of its own. The transcript stays
/// on screen throughout so the user can see what was heard, since spotting a
/// misheard amount matters more than a tidy interface.
struct ConversationalInvoiceView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var onInvoiceCreated: (String) -> Void

    @StateObject private var session = VoiceSessionController()
    @StateObject private var dialogue: DialogueManager
    @State private var resolver: VoiceEntityResolver?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let parser = SlotParser()

    init(defaultTaxRate: Double, resolveCustomer: @escaping (String) -> (id: String, name: String)?, onInvoiceCreated: @escaping (String) -> Void) {
        self.onInvoiceCreated = onInvoiceCreated
        _dialogue = StateObject(wrappedValue: DialogueManager(
            defaultTaxRate: defaultTaxRate,
            resolveCustomer: resolveCustomer
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(session.exchanges) { exchange in
                            bubble(exchange)
                                .id(exchange.id)
                        }

                        if !session.partialTranscript.isEmpty {
                            bubble(.init(speaker: .user, text: session.partialTranscript))
                                .opacity(0.55)
                                .id("partial")
                        }

                        if dialogue.draft.isReadyToConfirm {
                            draftSummary
                                .padding(.top, 4)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.exchanges.count) { _, _ in
                    withAnimation { proxy.scrollTo(session.exchanges.last?.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("New invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        session.stop()
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await beginSession() }
            .onDisappear { session.stop() }
            .onChange(of: dialogue.isComplete) { _, done in
                if done { Task { await saveInvoice() } }
            }
        }
    }

    // MARK: - Pieces

    private func bubble(_ exchange: VoiceSessionController.Exchange) -> some View {
        HStack {
            if exchange.speaker == .user { Spacer(minLength: 40) }
            Text(exchange.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(exchange.speaker == .user ? .white : Color.primary)
                .background(
                    exchange.speaker == .user ? AppTheme.infoBlue : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            if exchange.speaker == .app { Spacer(minLength: 40) }
        }
    }

    private var draftSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = dialogue.draft.customerName {
                Text(name).font(.subheadline.weight(.semibold))
            }
            ForEach(dialogue.draft.completeItems) { item in
                HStack {
                    Text(item.description).font(.caption)
                    Spacer(minLength: 8)
                    Text(money(item.amount)).font(.caption.weight(.semibold))
                }
            }
            Divider()
            HStack {
                Text("Total").font(.caption.weight(.semibold))
                Spacer()
                Text(money(dialogue.draft.total))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.revenueGreen)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                switch session.state {
                case .speaking:
                    session.bargeIn()
                case .idle, .failed:
                    Task { await beginSession() }
                default:
                    session.stop()
                }
                Haptics.light()
            } label: {
                Image(systemName: session.state.isActive ? "stop.fill" : "mic.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(session.state.isActive ? Color.red : AppTheme.infoBlue, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var statusLine: String {
        switch session.state {
        case .idle: return isSaving ? "Saving" : "Tap to start"
        case .listening: return "Listening"
        case .thinking: return "One moment"
        case .speaking: return "Tap to interrupt"
        case .failed(let message): return message
        }
    }

    // MARK: - Wiring

    private func beginSession() async {
        let entities = VoiceEntityResolver(customers: store.customers, savedItems: store.savedItems)
        resolver = entities

        session.contextualStrings = entities.recognitionVocabulary
        session.onTurn = { utterance in
            let intent = parser.parse(
                utterance,
                gap: dialogue.draft.nextGap,
                isConfirming: dialogue.isAwaitingConfirmation
            )
            if case .cancel = intent {
                session.stop()
                dismiss()
                return nil
            }
            return dialogue.handle(intent)
        }

        await session.start()
        session.say(dialogue.opening())
    }

    private func saveInvoice() async {
        guard let customerId = dialogue.draft.customerId, !isSaving else { return }
        let items = dialogue.draft.completeItems.map {
            InvoiceItem(description: $0.description, quantity: $0.quantity ?? 0, unitPrice: $0.unitPrice ?? 0)
        }
        guard !items.isEmpty else { return }

        isSaving = true
        session.stop()
        defer { isSaving = false }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let today = Date()
        let due = Calendar.current.date(
            byAdding: .day,
            value: store.defaultInvoiceDueDaysFromInvoiceDate,
            to: today
        ) ?? today

        do {
            let invoice = try await store.addInvoice(
                customerId: customerId,
                items: items,
                taxRate: dialogue.draft.taxRate ?? 0,
                date: formatter.string(from: today),
                dueDate: formatter.string(from: due),
                notes: dialogue.draft.notes,
                terms: nil
            )
            Haptics.success()
            onInvoiceCreated(invoice.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func money(_ value: Double) -> String {
        InvoiceLogic.formatCurrency(amount: value, code: store.companyProfile?.currency ?? "GBP")
    }
}
