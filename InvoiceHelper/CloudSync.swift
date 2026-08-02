import Combine
import Foundation
import SwiftUI

// MARK: - User defaults keys

private enum CloudSyncKeys {
    static let autoSyncEnabled = "cloudSync.autoSyncEnabled"
    static let intervalMinutes = "cloudSync.intervalMinutes"
    static let lastSyncedAt = "cloudSync.lastSyncedAt"
}

/// Presets for automatic sync (0 = manual only).
enum CloudSyncInterval: Int, CaseIterable, Identifiable {
    case manualOnly = 0
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case sixHours = 360

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manualOnly: return "Manual only"
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .oneHour: return "Every hour"
        case .twoHours: return "Every 2 hours"
        case .sixHours: return "Every 6 hours"
        }
    }
}

// MARK: - Dummy remote API (no real backend)

enum DummyCloudAPI {
    /// Placeholder endpoint shown in UI — not called with real credentials.
    static let placeholderEndpoint = "https://api.invoicehelper.example.com/v1/sync"

    private static let dummyCloudPayloadKey = "dummyCloud.lastExportPayload"

    /// Simulates uploading a full backup JSON to the dummy cloud (stored in `UserDefaults`).
    static func pushExportData(_ data: Data) async throws {
        UserDefaults.standard.set(data, forKey: dummyCloudPayloadKey)
        try await Task.sleep(nanoseconds: 700_000_000)
    }

    /// Simulates downloading the last pushed snapshot from the dummy cloud.
    static func pullExportData() async throws -> Data {
        try await Task.sleep(nanoseconds: 700_000_000)
        guard let data = UserDefaults.standard.data(forKey: dummyCloudPayloadKey), !data.isEmpty else {
            throw NSError(
                domain: "InvoiceHelper",
                code: 9001,
                userInfo: [NSLocalizedDescriptionKey: "No cloud snapshot yet. Upload data with “Sync to cloud” first."]
            )
        }
        return data
    }
}

// MARK: - Controller

@MainActor
final class CloudSyncController: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    /// When off, automatic sync is disabled (manual still available if you add a button elsewhere).
    @Published var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: CloudSyncKeys.autoSyncEnabled) }
    }

    @Published var intervalMinutes: Int {
        didSet { UserDefaults.standard.set(intervalMinutes, forKey: CloudSyncKeys.intervalMinutes) }
    }

    private weak var store: AppStore?
    private var timerCancellable: AnyCancellable?

    init() {
        autoSyncEnabled = UserDefaults.standard.object(forKey: CloudSyncKeys.autoSyncEnabled) as? Bool ?? true
        let saved = UserDefaults.standard.object(forKey: CloudSyncKeys.intervalMinutes) as? Int ?? CloudSyncInterval.thirtyMinutes.rawValue
        intervalMinutes = saved
        if let t = UserDefaults.standard.object(forKey: CloudSyncKeys.lastSyncedAt) as? TimeInterval {
            lastSyncedAt = Date(timeIntervalSince1970: t)
        }
        rescheduleTimer()
    }

    func attach(store: AppStore) {
        self.store = store
        rescheduleTimer()
    }

    func rescheduleTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        guard let store, store.isPremiumSubscriber else { return }
        guard autoSyncEnabled, intervalMinutes > 0 else { return }
        let seconds = TimeInterval(intervalMinutes * 60)
        timerCancellable = Timer.publish(every: seconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.syncNow() }
            }
    }

    /// Manual or timer-driven upload (local → dummy cloud).
    func syncNow() async {
        guard !isSyncing else { return }
        guard let store else {
            lastError = "Data not ready."
            return
        }
        guard store.isPremiumSubscriber else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            let data = try store.exportData()
            try await DummyCloudAPI.pushExportData(data)
            let now = Date()
            lastSyncedAt = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: CloudSyncKeys.lastSyncedAt)
            Haptics.success()
        } catch {
            lastError = error.localizedDescription
            Haptics.warning()
        }
    }

    /// Download dummy cloud snapshot and merge into local storage (keeps login / users).
    func pullFromCloud() async {
        guard !isSyncing else { return }
        guard let store else {
            lastError = "Data not ready."
            return
        }
        guard store.isPremiumSubscriber else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            let data = try await DummyCloudAPI.pullExportData()
            try await store.applyCloudSnapshot(data)
            let now = Date()
            lastSyncedAt = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: CloudSyncKeys.lastSyncedAt)
            Haptics.success()
        } catch {
            lastError = error.localizedDescription
            Haptics.warning()
        }
    }
}

// MARK: - Settings UI

struct CloudSyncSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var cloudSync: CloudSyncController
    @State private var showPremiumRequired = false

    private var intervalBinding: Binding<CloudSyncInterval> {
        Binding(
            get: { CloudSyncInterval(rawValue: cloudSync.intervalMinutes) ?? .thirtyMinutes },
            set: { new in
                cloudSync.intervalMinutes = new.rawValue
                cloudSync.rescheduleTimer()
            }
        )
    }

    private var premiumAutoSyncBinding: Binding<Bool> {
        Binding(
            get: { cloudSync.autoSyncEnabled },
            set: { new in
                if new, !store.isPremiumSubscriber {
                    showPremiumRequired = true
                    return
                }
                cloudSync.autoSyncEnabled = new
                cloudSync.rescheduleTimer()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Automatic sync", isOn: premiumAutoSyncBinding)
                Picker("Sync frequency", selection: intervalBinding) {
                    ForEach(CloudSyncInterval.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .disabled(!store.isPremiumSubscriber || !cloudSync.autoSyncEnabled)
            } footer: {
                Text(store.isPremiumSubscriber
                    ? "When automatic sync is on, your local data is uploaded to the dummy cloud on the schedule you choose."
                    : "Automatic sync is a Premium feature. Upgrade to schedule uploads.")
            }

            Section {
                Button {
                    if store.isPremiumSubscriber {
                        Task { await cloudSync.syncNow() }
                    } else {
                        showPremiumRequired = true
                    }
                } label: {
                    HStack {
                        if cloudSync.isSyncing {
                            ProgressView()
                                .padding(.trailing, 6)
                        }
                        Text("Sync to cloud")
                    }
                }
                .disabled(cloudSync.isSyncing)

                Button {
                    if store.isPremiumSubscriber {
                        Task { await cloudSync.pullFromCloud() }
                    } else {
                        showPremiumRequired = true
                    }
                } label: {
                    HStack {
                        if cloudSync.isSyncing {
                            ProgressView()
                                .padding(.trailing, 6)
                        }
                        Text("Download from cloud")
                    }
                }
                .disabled(cloudSync.isSyncing)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("“Sync to cloud” uploads a full backup to the in-app dummy store. “Download from cloud” replaces local customers, invoices, estimates, and jobs with that snapshot (your account login is kept).")
                    Text("Endpoint: \(DummyCloudAPI.placeholderEndpoint)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let at = cloudSync.lastSyncedAt {
                Section("Status") {
                    LabeledContent("Last synced") {
                        Text(at, style: .date)
                            .fontWeight(.medium)
                        Text(at, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let err = cloudSync.lastError {
                Section {
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Cloud sync")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cloudSync.rescheduleTimer()
        }
        .alert("Premium required", isPresented: $showPremiumRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cloud sync is a Premium feature. Upgrade to Premium to back up and restore your data from the cloud.")
        }
    }
}
