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

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// Text on light card surfaces (white / secondary grouped) in light mode.
    private var cardForegroundOnLight: Color {
        colorScheme == .light ? .black : Color.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: grid, spacing: 12) {
                metricCard(
                    title: "Total revenue",
                    value: formatted(store.totalRevenueCollected),
                    tint: AppTheme.revenueGreen
                )
                metricCard(
                    title: "Outstanding",
                    value: formatted(store.outstandingAmount),
                    tint: AppTheme.outstandingRed
                )
                metricCard(
                    title: "\(store.pendingDraftOrSentInvoices.count) Pending",
                    value: formatted(store.pendingDraftOrSentAmount),
                    tint: AppTheme.pendingOrange
                )
                metricCard(
                    title: "Overdue",
                    value: "\(store.overdueInvoiceCount)",
                    tint: AppTheme.outstandingRed
                )
                if showJobsTab {
                    NavigationLink {
                        JobListView(filter: .today)
                    } label: {
                        metricCardJobInline(
                            title: "Today's jobs",
                            value: "\(store.todaysActiveJobCount)",
                            tint: AppTheme.infoBlue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        JobListView(filter: .overdue(range: store.overdueJobsDashboardRange))
                    } label: {
                        metricCardJobInline(
                            title: "Overdue jobs",
                            value: "\(store.overduePendingJobsCount)",
                            tint: AppTheme.outstandingRed
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            quickActions
                .padding(.top, 10)

            recentSection
                .padding(.top, 12)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
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
                Text(welcomeLine)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    InvoiceEditorView(mode: .create, invoiceId: nil, onInvoiceCreated: { id in
                        invoicePreviewId = id
                        showInvoicePreview = true
                    })
                } label: {
                    Image(systemName: "plus.circle.fill")
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
            VoiceQuickEntrySheet { newInvoiceId in
                invoicePreviewId = newInvoiceId
                showInvoicePreview = true
            }
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

    private var welcomeLine: String {
        let name = store.companyProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { return "Welcome" }
        return "Welcome, \(name)"
    }

    /// Floating action button for dictating a new invoice.
    private var voiceFAB: some View {
        Button {
            Haptics.light()
            showVoiceQuickEntry = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(AppTheme.infoBlue, in: Circle())
                .shadow(color: AppTheme.infoBlue.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel("New invoice by voice")
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if store.companyProfile?.logo != nil {
            CompanyLogoImageView(logo: store.companyProfile?.logo, size: 36, clipCircle: true, scaleToFit: false, showsStroke: false)
        } else {
            Image(systemName: "building.2.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.infoBlue)
                .frame(width: 36, height: 36)
        }
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        metricCardLabel(title: title, value: value, tint: tint)
    }

    private func metricCardLabel(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(cardForegroundOnLight)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(cardForegroundOnLight)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.metricCardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(AppTheme.metricCardShadow), radius: 8, y: 2)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
    }

    /// Job metrics: title and value on one horizontal line.
    private func metricCardJobInline(title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(cardForegroundOnLight)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(cardForegroundOnLight)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.metricCardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(AppTheme.metricCardShadow), radius: 8, y: 2)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                NavigationLink {
                    InvoiceEditorView(mode: .create, invoiceId: nil, onInvoiceCreated: { id in
                        invoicePreviewId = id
                        showInvoicePreview = true
                    })
                } label: {
                    quickActionCard(
                        title: "New invoice",
                        systemImage: "doc.badge.plus",
                        tint: AppTheme.infoBlue
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    CustomerEditorView(customer: nil, onCustomerCreated: { id in
                        customerPreviewId = id
                        showCustomerPreview = true
                    })
                } label: {
                    quickActionCard(
                        title: "Add customer",
                        systemImage: "person.badge.plus",
                        tint: AppTheme.revenueGreen
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    EstimateListView()
                } label: {
                    quickActionCard(
                        title: "Estimates",
                        systemImage: "doc.questionmark",
                        tint: AppTheme.pendingOrange
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Compact row: icon leading, title trailing; matches metric card chrome.
    private func quickActionCard(title: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20, alignment: .leading)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(cardForegroundOnLight)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.metricCardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(AppTheme.metricCardShadow), radius: 8, y: 2)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 4)
                .padding(.vertical, 8)
        }
    }

    private var recentSection: some View {
        let recent = Array(store.invoices.sorted { $0.createdAt > $1.createdAt }.prefix(10))
        let currency = store.companyProfile?.currency ?? "GBP"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent invoices")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink("See all") {
                    InvoiceListView()
                }
                .font(.subheadline.weight(.semibold))
            }

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
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            if index < recent.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .refreshable {
                Haptics.light()
                store.reloadEstimates()
                await store.reloadInvoices()
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
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
