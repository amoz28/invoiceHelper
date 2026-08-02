import SwiftUI

@main
struct InvoiceHelperApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var cloudSync = CloudSyncController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(cloudSync)
                .task {
                    await store.bootstrap()
                    cloudSync.attach(store: store)
                }
        }
    }
}
