import SwiftUI

struct AuthContainerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isRegister = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("InvoiceHelper")
                    .font(.largeTitle.bold())
                Text("Invoices, estimates, jobs, and customers — stored on device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Picker("", selection: $isRegister) {
                    Text("Log in").tag(false)
                    Text("Register").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if isRegister {
                    RegisterView()
                } else {
                    LoginView()
                }
                Spacer()
            }
            .padding(.top, 32)
            .navigationBarHidden(true)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            if let message {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
            Section {
                Button("Log in") {
                    message = nil
                    do {
                        try store.login(email: email, password: password)
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(email.isEmpty || password.isEmpty)

                NavigationLink {
                    ResetPasswordView()
                } label: {
                    Text("Forgot password?")
                }
            }
        }
    }
}

struct ResetPasswordView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message: String?
    @State private var didSucceed = false

    var body: some View {
        Form {
            Section {
                TextField("Account email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                Text("Use the same email you registered with. Reset happens on this device only (no email is sent). Your new password must be at least 8 characters and include upper and lower case letters and a number.")
                    .font(.caption)
            }
            if let message {
                Section {
                    Text(message).foregroundStyle(didSucceed ? .green : .red)
                }
            }
            Section {
                Button("Reset password") {
                    submit()
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
            }
        }
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        message = nil
        didSucceed = false
        guard newPassword == confirmPassword else {
            message = "New passwords do not match."
            return
        }
        do {
            try store.resetPassword(email: email, newPassword: newPassword)
            didSucceed = true
            message = "Password updated. Go back and sign in with your new password."
        } catch {
            message = error.localizedDescription
        }
    }
}

struct RegisterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var companyName = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Company name", text: $companyName)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
            }
            if let message {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
            Section {
                Button("Create account") {
                    message = nil
                    do {
                        try store.register(email: email, password: password, companyName: companyName)
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(companyName.count < 2 || email.isEmpty || password.isEmpty)
            }
        }
    }
}

struct CompanyProfileSetupView: View {
    @EnvironmentObject private var store: AppStore
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
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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
                    TextField("State / region *", text: $state)
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
                    TextField("Payment link (optional)", text: $paymentLink)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
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
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Save and continue") { save() }
                        .buttonStyle(PrimaryFormButtonStyle())
                        .disabled(!isValid)
                }
            }
            .navigationTitle("Company profile")
        }
        .onAppear {
            if let u = store.currentUser {
                if name.isEmpty { name = u.companyName }
                if email.isEmpty { email = u.email }
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty && InvoiceLogic.validateEmail(email) && !phone.isEmpty
            && !street.isEmpty && !city.isEmpty && !state.isEmpty && !postalCode.isEmpty
            && !accountName.isEmpty && !accountNumber.isEmpty
    }

    private func save() {
        errorMessage = nil
        let profile = CompanyProfile(
            id: InvoiceLogic.generateId(),
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
            defaultInvoiceDueDaysFromInvoiceDate: nil,
            defaultEstimateValidDaysFromCreation: nil
        )
        do {
            try store.saveCompanyProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var store: AppStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message: String?
    @State private var didSucceed = false

    private var accountHasPassword: Bool {
        guard let p = store.currentUser?.password else { return false }
        return !p.isEmpty
    }

    var body: some View {
        Form {
            Section {
                if accountHasPassword {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                } else {
                    Text("No password is set on this account (for example after importing a backup). Choose a new password below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                Text("At least 8 characters with upper and lower case letters and a number.")
                    .font(.caption)
            }
            if let message {
                Section {
                    Text(message).foregroundStyle(didSucceed ? .green : .red)
                }
            }
            Section {
                Button("Update password") {
                    submit()
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(
                    newPassword.isEmpty || confirmPassword.isEmpty
                        || (accountHasPassword && currentPassword.isEmpty)
                )
            }
        }
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        message = nil
        didSucceed = false
        guard newPassword == confirmPassword else {
            message = "New passwords do not match."
            return
        }
        do {
            try store.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            didSucceed = true
            message = "Your password has been updated."
        } catch {
            message = error.localizedDescription
        }
    }
}
