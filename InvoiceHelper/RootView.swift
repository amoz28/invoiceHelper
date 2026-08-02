import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.isBootstrapping {
                SplashScreenView()
            } else if !store.isAuthenticated {
                AuthContainerView()
            } else if store.needsCompanySetup {
                CompanyProfileSetupView()
            } else {
                MainTabView()
            }
        }
    }
}
