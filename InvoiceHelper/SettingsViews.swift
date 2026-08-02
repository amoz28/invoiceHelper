import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppPreferences.Keys.showJobsTab) private var showJobsTab = true
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section("Company") {
                NavigationLink {
                    CompanyProfileEditView()
                } label: {
                    HStack(spacing: 14) {
                        CompanyLogoImageView(logo: store.companyProfile?.logo, size: 48, clipCircle: false, scaleToFit: true)
                            .background(Color(.secondarySystemFill))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Company profile")
                                .font(.headline)
                            Text(store.companyProfile?.name ?? "Not set")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Account") {
                NavigationLink("Change password") {
                    ChangePasswordView()
                }
            }
            Section("Sales") {
                NavigationLink("Estimates & quotes") {
                    EstimateListView()
                }
                NavigationLink {
                    SavedItemsSettingsView()
                } label: {
                    Label("Saved line items", systemImage: "list.bullet.rectangle")
                }
            }
            Section {
                Toggle(isOn: $showJobsTab) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jobs")
                        Text("Show the Jobs tab and job-related shortcuts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Jobs tab")
                .accessibilityHint("When off, Jobs is removed from the bottom tab bar.")
                if showJobsTab {
                    NavigationLink {
                        SavedJobTemplatesSettingsView()
                    } label: {
                        Label("Saved job templates", systemImage: "calendar.badge.clock")
                    }
                }
            } header: {
                Text("Customize")
            } footer: {
                Text("Choose what appears in the app. For now only Jobs is optional. When off, the Jobs tab is removed from the bottom tab bar. Dashboard job cards and the Jobs segment on customer profiles are hidden too. More tab options may be added later. Saved job templates stay on this device.")
                    .font(.caption)
            }
            Section("Data") {
                NavigationLink("Cloud sync") {
                    CloudSyncSettingsView()
                }
                NavigationLink("Export backup (JSON)") {
                    DataExportView()
                }
                NavigationLink("Import backup (JSON)") {
                    DataImportView()
                }
            }
            Section("Legal & privacy") {
                NavigationLink("Privacy Policy") {
                    PrivacyPolicyView()
                }
                NavigationLink("Terms of Use") {
                    TermsOfUseView()
                }
                NavigationLink("Publishing & App Store checklist") {
                    PublishingGuideView()
                }
            }
            Section {
                Button("Log out", role: .destructive) {
                    confirmLogout = true
                }
            }
            Section("About") {
                LabeledContent("App", value: "InvoiceHelper")
                LabeledContent("Version", value: "\(AppMetadata.marketingVersion) (\(AppMetadata.buildNumber))")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Log out of InvoiceHelper?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                try? store.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again to access your data on this device.")
        }
    }
}

struct CompanyProfileEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var website = ""
    @State private var paymentLink = ""
    @State private var street = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postalCode = ""
    @State private var country = ""
    @State private var accountName = ""
    @State private var accountNumber = ""
    @State private var bankName = ""
    @State private var swiftCode = ""
    @State private var sortCode = ""
    @State private var iban = ""
    @State private var taxId = ""
    @State private var currencyCode = "GBP"
    @State private var logoDataURI: String?
    @State private var invoiceDueDaysOffset = 0
    @State private var estimateValidDaysOffset = 0
    @State private var errorMessage: String?
    @State private var confirmSave = false

    var body: some View {
        Form {
            CompanyLogoSection(logoDataURI: $logoDataURI)
            Section("Company") {
                TextField("Company name *", text: $name)
                TextField("Email *", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Phone *", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Website (optional)", text: $website)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
            }
            Section("Billing address") {
                TextField("Street *", text: $street)
                TextField("City *", text: $city)
                TextField("State *", text: $state)
                TextField("Postal code *", text: $postalCode)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Country (optional)", text: $country)
            }
            Section("Bank details") {
                TextField("Account name *", text: $accountName)
                TextField("Account number *", text: $accountNumber)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Sort code (optional)", text: $sortCode)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Bank name (optional)", text: $bankName)
                TextField("SWIFT (optional)", text: $swiftCode)
                    .textInputAutocapitalization(.characters)
                TextField("IBAN (optional)", text: $iban)
                    .textInputAutocapitalization(.never)
                TextField("Payment link (optional)", text: $paymentLink, axis: .vertical)
                    .lineLimit(1...2)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .font(.body)
                Text("Shown on invoices as a clickable link (e.g. pay online page).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Tax & currency") {
                TextField("VAT Reg No (optional)", text: $taxId)
                Picker("Currency", selection: $currencyCode) {
                    ForEach(InvoiceLogic.currencies) { c in
                        Text("\(c.code) — \(c.name)").tag(c.code)
                    }
                }
            }
            Section("Default dates") {
                Stepper(value: $invoiceDueDaysOffset, in: 0...120) {
                    Text("Invoice due: \(invoiceDueDaysOffset) day\(invoiceDueDaysOffset == 1 ? "" : "s") after invoice date")
                }
                Stepper(value: $estimateValidDaysOffset, in: 0...120) {
                    Text("Estimate valid until: \(estimateValidDaysOffset) day\(estimateValidDaysOffset == 1 ? "" : "s") after creation")
                }
                Text("0 days means the same calendar day as the invoice date or creation date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            Section {
                Button("Save") { confirmSave = true }
                    .buttonStyle(PrimaryFormButtonStyle())
                    .disabled(!isValid)
            }
        }
        .navigationTitle("Company profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Save company profile?", isPresented: $confirmSave, titleVisibility: .visible) {
            Button("Save", role: .none) { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your company and billing details will be updated for new invoices and estimates.")
        }
        .onAppear {
            guard let p = store.companyProfile else { return }
            logoDataURI = p.logo
            name = p.name
            email = p.email
            phone = p.phone
            website = p.website ?? ""
            paymentLink = p.paymentLink ?? ""
            street = p.billingAddress.street
            city = p.billingAddress.city
            state = p.billingAddress.state
            postalCode = p.billingAddress.postalCode
            country = p.billingAddress.country
            accountName = p.bankDetails.accountName
            accountNumber = p.bankDetails.accountNumber
            bankName = p.bankDetails.bankName
            swiftCode = p.bankDetails.swiftCode
            sortCode = p.bankDetails.sortCode ?? ""
            iban = p.bankDetails.iban ?? ""
            taxId = p.taxId ?? ""
            currencyCode = p.currency
            invoiceDueDaysOffset = p.defaultInvoiceDueDaysFromInvoiceDate ?? 0
            estimateValidDaysOffset = p.defaultEstimateValidDaysFromCreation ?? 0
        }
    }

    private var isValid: Bool {
        !name.isEmpty && InvoiceLogic.validateEmail(email) && !phone.isEmpty
            && !street.isEmpty && !city.isEmpty && !state.isEmpty && !postalCode.isEmpty
            && !accountName.isEmpty && !accountNumber.isEmpty
    }

    private func save() {
        errorMessage = nil
        let id = store.companyProfile?.id ?? InvoiceLogic.generateId()
        let profile = CompanyProfile(
            id: id,
            name: name,
            email: email,
            phone: phone,
            website: website.isEmpty ? nil : website,
            paymentLink: paymentLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : paymentLink.trimmingCharacters(in: .whitespacesAndNewlines),
            billingAddress: Address(
                street: street,
                city: city,
                state: state,
                postalCode: postalCode,
                country: country.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            bankDetails: BankDetails(
                accountName: accountName,
                accountNumber: accountNumber,
                bankName: bankName.trimmingCharacters(in: .whitespacesAndNewlines),
                swiftCode: swiftCode.trimmingCharacters(in: .whitespacesAndNewlines),
                sortCode: sortCode.isEmpty ? nil : sortCode,
                iban: iban.isEmpty ? nil : iban
            ),
            currency: currencyCode,
            taxId: taxId.isEmpty ? nil : taxId,
            logo: logoDataURI,
            isProfileComplete: true,
            defaultInvoiceDueDaysFromInvoiceDate: invoiceDueDaysOffset,
            defaultEstimateValidDaysFromCreation: estimateValidDaysOffset
        )
        do {
            try store.saveCompanyProfile(profile)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DataExportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var errorMessage: String?
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text("Export matches InvoiceHelper JSON shape (users without passwords, payments separate).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share backup file", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Prepare export file") {
                do {
                    let data = try store.exportData()
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("invoicehelper-backup.json")
                    try data.write(to: url, options: .atomic)
                    exportURL = url
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .buttonStyle(.bordered)
        }
        .navigationTitle("Export")
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

struct DataImportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showPicker = false
    @State private var message: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Import replaces all local data (same behavior as InvoiceHelper). You may need to log in again; imported users have empty passwords.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Button("Choose JSON file…") {
                showPicker = true
            }
            .buttonStyle(.borderedProminent)
            if isImporting { ProgressView() }
        }
        .navigationTitle("Import")
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    isImporting = true
                    defer { isImporting = false }
                    do {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        try await store.importData(data)
                        message = "Import complete. Log in if required."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            case .failure(let err):
                message = err.localizedDescription
            }
        }
        .alert("Import", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

// MARK: - Saved line items (catalog for invoices & estimates)

struct SavedItemsSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var itemToDelete: SavedItem?
    @State private var confirmDelete = false

    private var currencyCode: String { store.companyProfile?.currency ?? "GBP" }

    var body: some View {
        Group {
            if store.savedItems.isEmpty {
                ContentUnavailableView {
                    Label("No saved line items", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Add products or services you use often. You can insert them when creating invoices and estimates.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.savedItems) { item in
                        NavigationLink {
                            SavedItemEditView(item: item)
                        } label: {
                            savedItemRow(item)
                        }
                    }
                    .onDelete { indexSet in
                        guard let i = indexSet.first else { return }
                        itemToDelete = store.savedItems[i]
                        confirmDelete = true
                    }
                }
            }
        }
        .navigationTitle("Saved line items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SavedItemEditView(item: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add saved line item")
            }
        }
        .confirmationDialog(
            "Delete “\(itemToDelete?.name ?? "")”?",
            isPresented: $confirmDelete,
            titleVisibility: .visible,
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                try? store.deleteSavedItem(id: item.id)
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: { _ in
            Text("This does not change existing invoices or estimates.")
        }
    }

    private func savedItemRow(_ item: SavedItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
            HStack(spacing: 6) {
                Text(InvoiceLogic.formatCurrency(amount: item.defaultUnitPrice, code: currencyCode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Text("Qty \(formatQty(item.defaultQuantity))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let d = item.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                Text(d)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatQty(_ q: Double) -> String {
        q == floor(q) ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }
}

struct SavedItemEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// `nil` = create new.
    let item: SavedItem?

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var quantity = "1"
    @State private var unitPrice = ""
    @State private var errorMessage: String?

    private var currencyCode: String { store.companyProfile?.currency ?? "GBP" }

    private var isEditing: Bool { item != nil }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return false }
        let q = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0
        let p = Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
        return q > 0 && p > 0
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                    .lineLimit(2...6)
            } footer: {
                Text("The description is used as the line text on invoices and estimates. If you leave it empty, the name is used.")
                    .font(.caption)
            }
            Section("Defaults for new lines") {
                TextField("Quantity", text: $quantity)
                    .keyboardType(.decimalPad)
                TextField("Unit price (\(currencyCode))", text: $unitPrice)
                    .keyboardType(.decimalPad)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button(isEditing ? "Save changes" : "Add") {
                    save()
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(!canSave)
            }
        }
        .navigationTitle(isEditing ? "Edit item" : "New item")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let item else { return }
            name = item.name
            descriptionText = item.description ?? ""
            quantity = formatQty(item.defaultQuantity)
            unitPrice = String(item.defaultUnitPrice)
        }
    }

    private func save() {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a name."
            return
        }
        let q = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0
        let p = Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard q > 0, p > 0 else {
            errorMessage = "Quantity and unit price must be greater than zero."
            return
        }
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let existing = item {
                var updated = existing
                updated.name = trimmedName
                updated.description = desc.isEmpty ? nil : desc
                updated.defaultQuantity = q
                updated.defaultUnitPrice = p
                try store.updateSavedItem(updated)
            } else {
                _ = try store.addSavedItem(
                    name: trimmedName,
                    description: desc.isEmpty ? nil : desc,
                    defaultQuantity: q,
                    defaultUnitPrice: p
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatQty(_ q: Double) -> String {
        q == floor(q) ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }
}

// MARK: - Saved job templates (separate from invoice line items)

struct SavedJobTemplatesSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var itemToDelete: SavedJobTemplate?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if store.savedJobTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No job templates", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Save common job titles and notes. They are only used when scheduling jobs, not on invoices.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.savedJobTemplates) { item in
                        NavigationLink {
                            SavedJobTemplateEditView(item: item)
                        } label: {
                            savedJobTemplateRow(item)
                        }
                    }
                    .onDelete { indexSet in
                        guard let i = indexSet.first else { return }
                        itemToDelete = store.savedJobTemplates[i]
                        confirmDelete = true
                    }
                }
            }
        }
        .navigationTitle("Saved job templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SavedJobTemplateEditView(item: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add job template")
            }
        }
        .confirmationDialog(
            "Delete “\(itemToDelete?.name ?? "")”?",
            isPresented: $confirmDelete,
            titleVisibility: .visible,
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                try? store.deleteSavedJobTemplate(id: item.id)
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: { _ in
            Text("This does not change existing scheduled jobs.")
        }
    }

    private func savedJobTemplateRow(_ item: SavedJobTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
            if let d = item.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                Text(d)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SavedJobTemplateEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let item: SavedJobTemplate?

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var errorMessage: String?

    private var isEditing: Bool { item != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $name)
                TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                    .lineLimit(2...8)
            } footer: {
                Text("Templates are for jobs only. Invoice line items are managed under Sales → Saved line items.")
                    .font(.caption)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button(isEditing ? "Save changes" : "Add") {
                    save()
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(!canSave)
            }
        }
        .navigationTitle(isEditing ? "Edit template" : "New template")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let item else { return }
            name = item.name
            descriptionText = item.description ?? ""
        }
    }

    private func save() {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a title."
            return
        }
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let existing = item {
                var updated = existing
                updated.name = trimmedName
                updated.description = desc.isEmpty ? nil : desc
                try store.updateSavedJobTemplate(updated)
            } else {
                _ = try store.addSavedJobTemplate(
                    name: trimmedName,
                    description: desc.isEmpty ? nil : desc
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
