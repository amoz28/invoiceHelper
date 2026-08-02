import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var cloudSync: CloudSyncController
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreferences.Keys.showJobsTab) private var showJobsTab = true
    @State private var tab = 0

    private var settingsTabTag: Int { showJobsTab ? 4 : 3 }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(0)
            NavigationStack { CustomerListView() }
                .tabItem { Label("Customers", systemImage: "person.2.fill") }
                .tag(1)
            NavigationStack { InvoiceListView() }
                .tabItem { Label("Invoices", systemImage: "doc.text.fill") }
                .tag(2)
            if showJobsTab {
                NavigationStack { JobListView() }
                    .tabItem { Label("Jobs", systemImage: "calendar") }
                    .tag(3)
            }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(settingsTabTag)
        }
        .tint(AppTheme.infoBlue)
        .onChange(of: showJobsTab) { _, enabled in
            if enabled {
                if tab == 3 { tab = 4 }
            } else {
                if tab == 3 { tab = 0 }
                else if tab == 4 { tab = 3 }
            }
        }
        .onChange(of: store.shouldSelectInvoicesTab) { _, should in
            if should {
                tab = 2
                store.shouldSelectInvoicesTab = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                cloudSync.rescheduleTimer()
            }
        }
    }
}
