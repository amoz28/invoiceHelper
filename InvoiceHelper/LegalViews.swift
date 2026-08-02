import SwiftUI

// MARK: - App metadata (About screen)

enum AppMetadata {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - Legal copy (templates — obtain jurisdiction-specific review before App Store release)

private enum LegalCopy {
    static let attorneyReviewBanner = """
    The texts below are templates for convenience only. They do not constitute legal advice. You should have a qualified attorney review and adapt them for your entity, jurisdiction, and how you actually operate and process data before publishing.
    """

    private static func longFormattedToday() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: Date())
    }

    static var privacyPolicy: String {
        """
    Last updated: \(longFormattedToday())

    Introduction
    This Privacy Policy describes how InvoiceHelper (“the App”) handles information when you use the App on your device.

    Who is responsible
    The party who distributes the App (you or your company) is typically the controller of personal data you enter. Replace this paragraph with your legal name, address, and contact email for privacy requests.

    What the App does
    InvoiceHelper helps you manage invoices, estimates, customers, jobs, and related business data. Core data is stored locally on your device in application storage unless you use optional features described below.

    Data stored on your device
    • Account and sign-in data you provide (e.g. email, password credentials processed and stored locally).
    • Business data you create: customers, invoices, estimates, jobs, payments, company profile, and exports you generate.
    • Optional company logo images you select from your photo library (processed and stored as part of your profile data on device).

    We do not operate a central server for core app data as part of the default experience described in this template. Data remains on your device unless you use backup/export/import or optional sync features you enable.

    Optional cloud sync (if offered in your build)
    If Premium cloud sync is available, it may upload an encrypted or encoded backup of your data to a service you configure. Describe the actual provider, what is uploaded, retention, and security in your final policy. If sync is only a local dummy/demo store, state that clearly.

    Photo library
    The App may request access to your photo library only so you can choose a company logo. We do not upload your entire library; only the image you select is used as you direct.

    PDF and sharing
    When you export or share PDFs or files, those actions use the standard iOS share sheet. Data is shared only with destinations you choose.

    Analytics and advertising
    This template assumes no third-party analytics or ad SDKs. If you add any, disclose them here (name, purpose, data categories).

    Retention
    Data remains on device until you delete it in the App, remove the App, or use export/import as applicable. Describe any server retention if you add backend services.

    Your rights
    Depending on where you live (e.g. UK GDPR, EU GDPR, CCPA), you may have rights to access, correct, delete, or export personal data. You can export data where the App provides export, and delete app data by deleting the App or using in-app deletion features. For requests directed to the publisher, provide a contact email.

    Children
    The App is not intended for children under the age required by applicable law to consent to data processing. Do not use the App for children’s personal data in violation of law.

    International transfers
    If you only store data on device, state that processing occurs on the device. If you add cloud services, describe transfers and safeguards.

    Changes
    We may update this policy. Update the “Last updated” date and, where required, notify users in the App or by other means.

    Contact
    Replace with: privacy@yourdomain.com
    """
    }

    static var termsOfUse: String {
        """
    Last updated: \(longFormattedToday())

    Important
    These Terms of Use (“Terms”) are a template. Have them reviewed by a lawyer for your jurisdiction and business.

    Agreement
    By downloading or using InvoiceHelper, you agree to these Terms. If you do not agree, do not use the App.

    License
    Subject to these Terms, you receive a limited, non-exclusive, non-transferable licence to use the App for your internal business purposes in accordance with the App Store or other distribution terms.

    Not professional advice
    The App does not provide legal, tax, or accounting advice. You are responsible for compliance with laws and regulations applicable to your invoices, estimates, and business records.

    Your data and backups
    You are responsible for the accuracy of data you enter and for maintaining backups (e.g. export) where appropriate. We are not liable for loss of data due to device loss, uninstallation, or user error unless mandatory law says otherwise.

    Acceptable use
    You will not use the App for unlawful purposes, to infringe others’ rights, or to transmit malware. You will not attempt to reverse engineer the App except where permitted by law.

    Disclaimer
    THE APP IS PROVIDED “AS IS” WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, TO THE MAXIMUM EXTENT PERMITTED BY LAW.

    Limitation of liability
    TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE PUBLISHER SHALL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, DATA, OR GOODWILL. TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT YOU PAID FOR THE APP IN THE TWELVE MONTHS BEFORE THE CLAIM, OR IF NONE, ZERO.

    Some jurisdictions do not allow certain limitations; in those cases, limits apply only to the extent permitted.

    Indemnity
    You agree to indemnify and hold harmless the publisher from claims arising from your use of the App or your business data, to the extent permitted by law.

    Third-party services
    If the App integrates third-party services (e.g. payment links, cloud sync), those services have their own terms. Describe them in your final Terms.

    Termination
    You may stop using the App at any time. We may suspend or terminate access where required by law or for breach of these Terms.

    Governing law
    Replace with the laws and courts of [Your jurisdiction].

    Contact
    Replace with: support@yourdomain.com
    """
    }

    static let publishingGuide = """
    App Store & legal — pre-launch checklist (for developers)

    Apple App Store Connect (typical requirements)
    • Apple Developer Program membership paid and active.
    • App record created with bundle ID matching the Xcode project.
    • App Privacy questionnaire completed accurately (data types collected, linked to user, used for tracking, etc.). Align answers with this App’s real behaviour and any SDKs you add.
    • Age rating questionnaire completed honestly.
    • Screenshots and metadata for each device class you support; promotional text and description without misleading claims.
    • Export compliance / encryption: declare use of encryption (HTTPS, etc.) per Apple’s questions.
    • If you sell digital goods or subscriptions, use In-App Purchase and comply with App Review Guidelines.

    Legal documents
    • Privacy Policy URL or in-app Privacy Policy (you have in-app templates — host a URL too if Apple or users expect it).
    • Terms of Use / EULA as appropriate; link from App Store description or in-app if required.
    • Business registration and tax obligations for sales are your responsibility.

    Product & safety
    • Test on supported iOS versions; fix crashes and data-loss scenarios.
    • If you collect personal data from EU/UK users, ensure a lawful basis and GDPR compliance where applicable.
    • Accessibility: consider Dynamic Type, VoiceOver labels, and contrast for broader reach.

    InvoiceHelper-specific reminders
    • Local storage: clarify in Privacy Policy what stays on device vs any future backend.
    • Photo library: Info.plist must include a usage description (configured in the project for logo selection).
    • Premium / subscriptions: implement StoreKit 2 or equivalent and disclose pricing and renewal clearly.

    AI era — practical advisories (not legal advice)
    • Be transparent: if you later add AI features (e.g. draft invoice text), disclose what is sent where, retention, and whether humans review outputs.
    • Avoid uploading customers’ personal data to third-party LLM APIs without consent and a data processing assessment where required.
    • Marketing: focus on clear outcomes (time saved, fewer errors) rather than vague “AI-powered” claims that App Review may scrutinise.
    • Accuracy: invoice and tax figures must remain user-verified; any AI assistance should be labelled as assistive, not authoritative.
    • Intellectual property: do not train public models on user data without permission; prefer on-device or contracted enterprise APIs with clear terms.

    Replace placeholder contact emails and jurisdiction in the Privacy Policy and Terms before release.
    """
}

// MARK: - Views

struct PrivacyPolicyView: View {
    var body: some View {
        LegalScrollDocumentView(
            title: "Privacy Policy",
            bodyText: LegalCopy.privacyPolicy,
            banner: LegalCopy.attorneyReviewBanner
        )
    }
}

struct TermsOfUseView: View {
    var body: some View {
        LegalScrollDocumentView(
            title: "Terms of Use",
            bodyText: LegalCopy.termsOfUse,
            banner: LegalCopy.attorneyReviewBanner
        )
    }
}

struct PublishingGuideView: View {
    var body: some View {
        LegalScrollDocumentView(
            title: "Publishing checklist",
            bodyText: LegalCopy.publishingGuide,
            banner: "Internal guide for developers and publishers. Update App Store Connect and legal documents to match your shipping product."
        )
    }
}

private struct LegalScrollDocumentView: View {
    let title: String
    let bodyText: String
    let banner: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
