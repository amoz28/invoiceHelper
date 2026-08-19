import SwiftUI

/// A form that talks. Every field is visible and editable from the start; the
/// conversation drives which one is focused rather than replacing the form.
///
/// The transcript-style UI this replaces could not support "fill by voice or type
/// instead" or "skip and come back", because there was nothing on screen to tap.
struct ConversationalInvoiceView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var onInvoiceCreated: (String) -> Void

    @StateObject private var session = VoiceSessionController()
    @StateObject private var dialogue: DialogueManager

    /// Not a separate @ObservedObject. SwiftUI re-runs init on every parent redraw:
    /// StateObject keeps the original manager while ObservedObject would take a
    /// freshly built draft, so the form would silently unbind from the draft that
    /// speech is filling. The manager republishes the draft's changes instead.
    private var draft: InvoiceDraft { dialogue.draft }

    @State private var showCustomerPicker = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Held until the keyboard closes: speaking over an open keyboard is both
    /// jarring and pointless, since the mic is suspended anyway.
    @State private var pendingLine: String?
    @FocusState private var typingField: SlotID?

    private let parser = SlotParser()

    init(
        resolveCustomer: @escaping (String) -> (id: String, name: String)?,
        customerCandidates: @escaping (String) -> [String] = { _ in [] },
        onInvoiceCreated: @escaping (String) -> Void
    ) {
        self.onInvoiceCreated = onInvoiceCreated
        _dialogue = StateObject(wrappedValue: DialogueManager(
            draft: InvoiceDraft(),
            resolveCustomer: resolveCustomer,
            customerCandidates: customerCandidates
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                customerSection
                ForEach(draft.items.indices, id: \.self) { index in
                    itemSection(index)
                }
                addItemRow
                taxSection
                totalsSection
                saveSection
            }
            .navigationTitle("New invoice")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { micBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        session.stop()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCustomerPicker, onDismiss: {
                session.resume()
                if let line = pendingLine {
                    pendingLine = nil
                    session.say(line)
                }
            }) {
                customerPicker
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
            .onChange(of: typingField) { previous, field in
                // A field counts as manually filled when focus leaves it, not on
                // every keystroke, otherwise typing 'Rewiring' would register as
                // eight separate fills and silence the app mid-word.
                if let previous {
                    let line = dialogue.recordManualFill(of: previous)
                    if let line, !dialogue.isQuiet { pendingLine = line }
                }

                // Typing and listening cannot share the room. While the keyboard is
                // up the recognizer would transcribe muttering into the focused
                // field, so the mic pauses and picks back up on dismiss.
                if let field {
                    dialogue.focus(field)
                    session.suspend()
                } else {
                    session.resume()
                    if let line = pendingLine {
                        pendingLine = nil
                        session.say(line)
                    }
                }
            }
            .onChange(of: dialogue.focusedSlot) { _, slot in
                // Voice moved on, so pull the keyboard off a field the user is no
                // longer being asked about.
                if let slot, typingField != nil, typingField != slot {
                    typingField = nil
                }
            }
        }
    }

    // MARK: - Sections

    private var customerSection: some View {
        Section {
            Button {
                dialogue.focus(.customer)
                session.suspend()
                showCustomerPicker = true
            } label: {
                HStack {
                    Text(draft.customerName ?? "Choose a customer")
                        .foregroundStyle(draft.customerName == nil ? .secondary : .primary)
                    Spacer()
                    slotBadge(.customer)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            sectionHeader("Customer", slot: .customer)
        }
    }

    private func itemSection(_ index: Int) -> some View {
        Section {
            TextField("What did you do?", text: Binding(
                get: { draft.items[safe: index]?.description ?? "" },
                set: { draft.setDescription($0, at: index) }
            ), axis: .vertical)
            .lineLimit(1...4)
            .focused($typingField, equals: .itemDescription(index))

            HStack {
                Text("Quantity")
                Spacer()
                TextField("1", text: numberBinding(
                    get: { draft.items[safe: index]?.quantity },
                    set: { draft.setQuantity($0, at: index) }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .focused($typingField, equals: .itemQuantity(index))
                slotBadge(.itemQuantity(index))
            }

            HStack {
                Text("Unit price")
                Spacer()
                TextField("0.00", text: numberBinding(
                    get: { draft.items[safe: index]?.unitPrice },
                    set: { draft.setUnitPrice($0, at: index) }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .focused($typingField, equals: .itemPrice(index))
                slotBadge(.itemPrice(index))
            }
        } header: {
            HStack {
                sectionHeader("Item \(index + 1)", slot: .itemDescription(index))
                Spacer()
                if draft.items.count > 1 {
                    Button("Remove") { draft.removeItem(at: index) }
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textCase(nil)
                }
            }
        }
    }

    private var addItemRow: some View {
        Section {
            Button {
                draft.appendItem()
                dialogue.focus(.itemDescription(draft.items.count - 1))
            } label: {
                Label("Add another item", systemImage: "plus.circle")
            }
        }
    }

    private var taxSection: some View {
        Section {
            Picker("Tax rate", selection: Binding(
                get: { draft.taxRate },
                set: { draft.setTaxRate($0) }
            )) {
                ForEach(InvoiceLogic.taxRates, id: \.self) { rate in
                    Text(rate == rate.rounded() ? String(format: "%.0f%%", rate) : String(format: "%.2f%%", rate))
                        .tag(rate)
                }
            }
        } header: {
            sectionHeader("Tax", slot: .taxRate)
        } footer: {
            if !draft.taxConfirmed {
                Text("Defaults to 20%.").font(.caption)
            }
        }
    }

    private var totalsSection: some View {
        Section {
            LabeledContent("Subtotal", value: money(draft.subtotal))
            LabeledContent("Tax", value: money(draft.tax))
            LabeledContent("Total") {
                Text(money(draft.total))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.revenueGreen)
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await saveInvoice() }
            } label: {
                if isSaving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Create invoice").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryFormButtonStyle())
            .disabled(!draft.canSave || isSaving)
        } footer: {
            if let reason = draft.saveBlockedReason {
                Text(reason).font(.caption)
            }
        }
    }

    // MARK: - Bits

    private func sectionHeader(_ title: String, slot: SlotID) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if dialogue.focusedSlot == slot {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.infoBlue)
            }
        }
    }

    /// Shows why a field is empty, so a skipped one reads as deliberate rather than
    /// forgotten, and an assumed value is visibly not something the user said.
    @ViewBuilder
    private func slotBadge(_ slot: SlotID) -> some View {
        switch draft.state(of: slot) {
        case .skipped, .skippedFinal:
            Text("Skipped")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        case .assumed:
            Text("Assumed")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        case .empty, .filled:
            EmptyView()
        }
    }

    private var micBar: some View {
        HStack(spacing: 16) {
            Button {
                switch session.state {
                case .speaking: session.bargeIn()
                case .idle, .failed: Task { await beginSession() }
                default: session.stop()
                }
                Haptics.light()
            } label: {
                Image(systemName: session.state.isActive ? "stop.fill" : "mic.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(session.state.isActive ? Color.red : AppTheme.infoBlue, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if !session.partialTranscript.isEmpty {
                    Text(session.partialTranscript)
                        .font(.caption)
                        .lineLimit(2)
                }
            }

            Spacer()

            if dialogue.isQuiet {
                Button {
                    dialogue.resumeSpeaking()
                    Haptics.light()
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Turn spoken prompts back on")
            }

            if let slot = dialogue.focusedSlot, session.state.isActive {
                Button("Skip") {
                    if let line = dialogue.handle(.skip) { session.say(line) }
                    Haptics.light()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(slot == .taxRate && draft.taxConfirmed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var customerPicker: some View {
        NavigationStack {
            List(store.customers) { customer in
                Button {
                    draft.setCustomer(id: customer.id, name: CustomerHeader.primary(customer))
                    pendingLine = dialogue.recordManualFill(of: .customer)
                    showCustomerPicker = false
                } label: {
                    Text(CustomerHeader.primary(customer))
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCustomerPicker = false }
                }
            }
        }
    }

    private var statusLine: String {
        switch session.state {
        case .idle: return isSaving ? "Saving" : "Tap to start"
        case .listening: return dialogue.isQuiet ? "Following along" : "Listening"
        case .thinking: return "One moment"
        case .speaking: return "Tap to interrupt"
        case .failed(let message): return message
        }
    }

    // MARK: - Wiring

    private func beginSession() async {
        let entities = VoiceEntityResolver(customers: store.customers, savedItems: store.savedItems)
        session.contextualStrings = entities.recognitionVocabulary
        session.onTurn = { utterance in
            let intent = parser.parse(
                utterance,
                gap: draft.nextGap,
                isConfirming: dialogue.isAwaitingConfirmation,
                awaitingDescriptionConfirm: dialogue.isAwaitingDescriptionConfirm
            )
            if case .cancel = intent {
                session.stop()
                dismiss()
                return nil
            }
            return dialogue.handle(intent)
        }

        // Permissions only — mic opens after the opening question finishes speaking.
        await session.start()
        session.say(dialogue.opening())
    }

    private func saveInvoice() async {
        guard draft.canSave, let customerId = draft.customerId, !isSaving else { return }
        let items = draft.completeItems.map {
            InvoiceItem(description: $0.description, quantity: $0.quantity ?? 1, unitPrice: $0.unitPrice ?? 0)
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
                taxRate: draft.taxRate,
                date: formatter.string(from: today),
                dueDate: formatter.string(from: due),
                notes: draft.notes,
                terms: nil
            )
            Haptics.success()
            onInvoiceCreated(invoice.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Keeps a partially typed number ("12.") intact instead of round-tripping it
    /// through Double and deleting the user's decimal point as they type.
    private func numberBinding(get: @escaping () -> Double?, set: @escaping (Double) -> Void) -> Binding<String> {
        Binding(
            get: {
                guard let value = get(), value > 0 else { return "" }
                return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
            },
            set: { text in
                let cleaned = text.replacingOccurrences(of: ",", with: ".")
                if let value = Double(cleaned) { set(value) }
            }
        )
    }

    private func money(_ value: Double) -> String {
        InvoiceLogic.formatCurrency(amount: value, code: store.companyProfile?.currency ?? "GBP")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
