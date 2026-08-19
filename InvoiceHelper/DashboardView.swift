import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.Keys.showJobsTab) private var showJobsTab = true

    @State private var invoicePreviewId: String?
    @State private var showInvoicePreview = false
    @State private var customerPreviewId: String?
    @State private var showCustomerPreview = false
    @State private var expandedInvoiceId: String?
    @State private var paymentSheetInvoiceId: String?
    @State private var pdfShareItem: SharePDFURL?
    @State private var invoiceListErrorMessage: String?
    @State private var showVoiceQuickEntry = false

    /// Text on light card surfaces (white / secondary grouped) in light mode.
    private var cardForegroundOnLight: Color {
        colorScheme == .light ? .black : Color.primary
    }

    private var greetingName: String {
        let name = store.companyProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name
    }

    private var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        let overdueInvoices = store.overdueInvoiceCount
        if overdueInvoices > 0 {
            items.append(.init(
                id: "overdue-invoices",
                count: "\(overdueInvoices)",
                label: overdueInvoices == 1 ? "Overdue invoice" : "Overdue invoices",
                systemImage: "exclamationmark.circle.fill",
                tint: AppTheme.outstandingRed,
                kind: .overdueInvoices
            ))
        }
        let pending = store.pendingDraftOrSentInvoices.count
        if pending > 0 {
            items.append(.init(
                id: "pending",
                count: "\(pending)",
                label: "Awaiting payment",
                systemImage: "clock.fill",
                tint: AppTheme.pendingOrange,
                kind: .pendingInvoices
            ))
        }
        if showJobsTab {
            let today = store.todaysActiveJobCount
            if today > 0 {
                items.append(.init(
                    id: "jobs-today",
                    count: "\(today)",
                    label: today == 1 ? "Job today" : "Jobs today",
                    systemImage: "calendar",
                    tint: AppTheme.infoBlue,
                    kind: .jobsToday
                ))
            }
            let overdueJobs = store.overduePendingJobsCount
            if overdueJobs > 0 {
                items.append(.init(
                    id: "jobs-overdue",
                    count: "\(overdueJobs)",
                    label: overdueJobs == 1 ? "Overdue job" : "Overdue jobs",
                    systemImage: "calendar.badge.exclamationmark",
                    tint: AppTheme.outstandingRed,
                    kind: .jobsOverdue
                ))
            }
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            moneySnapshot
            if !attentionItems.isEmpty {
                attentionSection
            }
            createSection
            recentSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) { voiceFAB }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: InvoiceDetailNavigationID.self) { route in
            InvoiceDetailView(invoiceId: route.invoiceId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    CompanyProfileEditView()
                } label: {
                    profileAvatar
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .accessibilityLabel("Company profile")
            }
            ToolbarItem(placement: .principal) {
                Text(greetingName.isEmpty ? "Home" : greetingName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    InvoiceEditorView(mode: .create, invoiceId: nil, onInvoiceCreated: { id in
                        invoicePreviewId = id
                        showInvoicePreview = true
                    })
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("New invoice")
            }
        }
        .sheet(isPresented: $showInvoicePreview) {
            if let id = invoicePreviewId {
                NavigationStack {
                    InvoiceDetailView(invoiceId: id)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showInvoicePreview = false
                                    invoicePreviewId = nil
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showVoiceQuickEntry) {
            ConversationalInvoiceView(
                resolveCustomer: { spoken in
                    VoiceEntityResolver(customers: store.customers, savedItems: store.savedItems)
                        .resolveCustomer(spoken)
                },
                customerCandidates: { spoken in
                    VoiceEntityResolver(customers: store.customers, savedItems: store.savedItems)
                        .customerCandidates(spoken)
                        .map { CustomerHeader.primary($0) }
                },
                onInvoiceCreated: { newInvoiceId in
                    invoicePreviewId = newInvoiceId
                    showInvoicePreview = true
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showCustomerPreview) {
            if let id = customerPreviewId {
                NavigationStack {
                    CustomerDetailByIdView(customerId: id)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showCustomerPreview = false
                                    customerPreviewId = nil
                                }
                            }
                        }
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { invoiceListErrorMessage != nil },
            set: { if !$0 { invoiceListErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { invoiceListErrorMessage = nil }
        } message: {
            Text(invoiceListErrorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { paymentSheetInvoiceId != nil },
            set: { if !$0 { paymentSheetInvoiceId = nil } }
        )) {
            if let id = paymentSheetInvoiceId, let inv = store.invoices.first(where: { $0.id == id }) {
                PaymentSheet(invoiceId: inv.id, maxRemaining: inv.total - InvoiceLogic.totalPaid(for: inv))
                    .environmentObject(store)
            }
        }
        .sheet(item: $pdfShareItem) { item in
            PDFActivityView(activityItems: [item.url]) { completed in
                if completed, let pid = item.invoiceIdForMarkSent,
                   let inv = store.invoices.first(where: { $0.id == pid }), inv.status == .draft {
                    Task {
                        try? await store.updateInvoice(id: inv.id) { $0.status = .sent }
                    }
                }
            }
        }
    }

    // MARK: - Money snapshot

    /// One card: outstanding is the actionable figure; collected is context.
    private var moneySnapshot: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Still to collect")
                        .font(.subheadline.weight(.medium))
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(AppTheme.outstandingRed)
                }
                .foregroundStyle(.secondary)

                Text(formatted(store.outstandingAmount))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(cardForegroundOnLight)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            Divider()

            HStack(spacing: 0) {
                moneyStat(
                    title: "Collected",
                    value: formatted(store.totalRevenueCollected),
                    tint: AppTheme.revenueGreen
                )
                Spacer(minLength: 12)
                moneyStat(
                    title: "Open invoices",
                    value: "\(store.pendingDraftOrSentInvoices.count)",
                    tint: AppTheme.pendingOrange
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    private func moneyStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(cardForegroundOnLight)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }

    // MARK: - Attention

    private var attentionSection: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(attentionItems) { item in
                attentionDestination(for: item)
            }
        }
    }

    @ViewBuilder
    private func attentionDestination(for item: AttentionItem) -> some View {
        switch item.kind {
        case .overdueInvoices:
            NavigationLink {
                InvoiceListView(focus: .overdue)
            } label: {
                attentionTile(item)
            }
            .buttonStyle(.plain)
        case .pendingInvoices:
            NavigationLink {
                InvoiceListView(focus: .awaitingPayment)
            } label: {
                attentionTile(item)
            }
            .buttonStyle(.plain)
        case .jobsToday:
            NavigationLink {
                JobListView(filter: .today)
            } label: {
                attentionTile(item)
            }
            .buttonStyle(.plain)
        case .jobsOverdue:
            NavigationLink {
                JobListView(filter: .overdue(range: store.overdueJobsDashboardRange))
            } label: {
                attentionTile(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func attentionTile(_ item: AttentionItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.tint)
                Text(item.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(item.count)
                .font(.title3.weight(.semibold))
                .foregroundStyle(cardForegroundOnLight)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.count) \(item.label)")
        .accessibilityHint("Opens related list")
    }

    // MARK: - Create

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                InvoiceEditorView(mode: .create, invoiceId: nil, onInvoiceCreated: { id in
                    invoicePreviewId = id
                    showInvoicePreview = true
                })
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.infoBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("New invoice")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(cardForegroundOnLight)
                        Text("Bill a customer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                NavigationLink {
                    CustomerEditorView(customer: nil, onCustomerCreated: { id in
                        customerPreviewId = id
                        showCustomerPreview = true
                    })
                } label: {
                    secondaryCreateChip(title: "Customer", systemImage: "person.badge.plus")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    EstimateListView()
                } label: {
                    secondaryCreateChip(title: "Estimates", systemImage: "doc.text")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func secondaryCreateChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.infoBlue)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cardForegroundOnLight)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        let recent = Array(store.invoices.sorted { $0.createdAt > $1.createdAt }.prefix(10))
        let currency = store.companyProfile?.currency ?? "GBP"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !recent.isEmpty {
                    NavigationLink("See all") {
                        InvoiceListView()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if recent.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No invoices yet")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Create one to see it here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 36)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, inv in
                            VStack(spacing: 0) {
                                InvoiceListRowWithLongPressActions(
                                    invoice: inv,
                                    customerLine: invoiceRecipientName(for: inv.customerId),
                                    totalFormatted: InvoiceLogic.formatCurrency(amount: inv.total, code: currency),
                                    foreground: cardForegroundOnLight,
                                    useValueNavigation: true,
                                    expandedInvoiceId: $expandedInvoiceId,
                                    paymentSheetInvoiceId: $paymentSheetInvoiceId,
                                    pdfShareItem: $pdfShareItem,
                                    listErrorMessage: $invoiceListErrorMessage
                                )
                                .environmentObject(store)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                if index < recent.count - 1 {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 72)
                }
                .scrollIndicators(.visible)
                .refreshable {
                    Haptics.light()
                    store.reloadEstimates()
                    await store.reloadInvoices()
                }
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
    }

    // MARK: - Chrome

    private var voiceFAB: some View {
        Button {
            Haptics.light()
            showVoiceQuickEntry = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppTheme.infoBlue, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("New invoice by voice")
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if store.companyProfile?.logo != nil {
            CompanyLogoImageView(logo: store.companyProfile?.logo, size: 36, clipCircle: true, scaleToFit: false, showsStroke: false)
        } else {
            Image(systemName: "building.2.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.infoBlue)
                .frame(width: 36, height: 36)
                .background(AppTheme.infoBlue.opacity(0.12), in: Circle())
        }
    }

    private func formatted(_ amount: Double) -> String {
        InvoiceLogic.formatCurrency(amount: amount, code: store.companyProfile?.currency ?? "GBP")
    }

    /// Legal / full customer name (`Customer.name`), not display name.
    private func invoiceRecipientName(for customerId: String) -> String {
        guard let c = store.customers.first(where: { $0.id == customerId }) else { return "Unknown customer" }
        let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Unknown customer" : n
    }
}

// MARK: - Attention model

private struct AttentionItem: Identifiable {
    enum Kind {
        case overdueInvoices
        case pendingInvoices
        case jobsToday
        case jobsOverdue
    }

    let id: String
    let count: String
    let label: String
    let systemImage: String
    let tint: Color
    let kind: Kind
}
