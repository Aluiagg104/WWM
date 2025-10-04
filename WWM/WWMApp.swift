import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseCore

@main
struct WWMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var userVM = CurrentUserViewModel()

    var body: some Scene {
        WindowGroup {
            RootSwitcher()                     // ⬅️ kein NavigationStack hier
                .environmentObject(userVM)
                .id(userVM.isSignedIn)         // Rebuild beim Auth-Wechsel
                .task { await userVM.loadProfile() }
                .task { userVM.startAuthListener() }
        }
    }
}

struct RootSwitcher: View {
    @EnvironmentObject var userVM: CurrentUserViewModel
    var body: some View {
        if userVM.isSignedIn {
            StartView()                        // Tabs kümmern sich selbst um Navigation
        } else {
            NavigationStack {                  // ⬅️ nur für Auth-Flow brauchen wir Navigation
                AuthenticationView()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}
