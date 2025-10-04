import SwiftUI

struct StartView: View {
    var body: some View {
        TabView {
            Tab("Feed", systemImage: "house.fill") {
                NavigationStack {
                    FeedView()
                        .navigationTitle("Feed")            // ✅ erscheint wieder
                        .navigationBarTitleDisplayMode(.large)
                }
            }
            Tab("Post", systemImage: "plus.app.fill") {
                NavigationStack {
                    PostView()
                        .navigationTitle("Neuer Post")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
            Tab("Profil", systemImage: "person.crop.circle.fill") {
                NavigationStack {
                    ProfileView()
                        .navigationTitle("Profil")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
    }
}
