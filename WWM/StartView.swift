import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct StartView: View {
    @State private var FreindsViewStatus: Bool = false
    
    var body: some View {
        TabView {
            Tab("Feed", systemImage: "house.fill") {
                NavigationStack {
                    FeedView()
                        .navigationTitle("Feed")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
            Tab("Post", systemImage: "plus.app.fill") {
                NavigationStack {
                    PostView()
                        .navigationTitle("Neuer Post")
                        .navigationBarTitleDisplayMode(.large)
                        .onAppear { FreindsViewStatus = false }
                }
            }
            Tab("Profil", systemImage: "person.fill") {
                NavigationStack {
                    ProfileView()
                        .navigationTitle("Neuer Post")
                        .navigationBarTitleDisplayMode(.large)
                        .onAppear { FreindsViewStatus = false }
                }
            }
            Tab("Freunde", systemImage: "person.2.fill") {
                NavigationStack {
                    FriendsView()
                        .navigationTitle("Freunde")
                        .navigationBarTitleDisplayMode(.large)
                        .onAppear { FreindsViewStatus = true }
                }
            }
            if FreindsViewStatus == true {
                Tab(role: .search) {
                    NavigationStack {
                        SearchView()
                            .navigationTitle("Suche")
                            .navigationBarTitleDisplayMode(.large)
                    }
                }
            }
        }
    }
}

struct SearchView: View {
    @State private var SearchText: String = ""

    @StateObject private var vm = FriendsViewModel()          // ← statt "private var"
    @StateObject private var unreadStore = UnreadPerChatStore()
    @State private var myUid: String = Auth.auth().currentUser?.uid ?? ""

    var filteredFriends: [AppUser] {
        if SearchText.isEmpty { return vm.friends }
        return vm.friends.filter { $0.localizedCaseInsensitiveContains(SearchText) }
    }
    
    var body: some View {
        List {
            ForEach(filteredFriends, id: \.uid) { friend in
                NavigationLink {
                    ChatView(user: friend)
                } label: {
                    GlassRow {
                        FriendRow(friend: friend, unreadCount: unreadCount(for: friend))
                            .contentShape(Rectangle())
                            .overlay(alignment: .trailing) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 6)
                            }
                    }
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .onAppear {
            myUid = Auth.auth().currentUser?.uid ?? ""
            vm.start()
            unreadStore.start()
        }
        .onDisappear {
            vm.stop()
            unreadStore.stop()
        }
        .searchable(text: $SearchText)
    }
    
    private func unreadCount(for friend: AppUser) -> Int {
        guard !myUid.isEmpty else { return 0 }
        let cid = chatIdBetween(me: myUid, other: friend.uid)
        return unreadStore.counts[cid] ?? 0
    }

    private func chatIdBetween(me: String, other: String) -> String {
        me < other ? "\(me)_\(other)" : "\(other)_\(me)"
    }
}

private struct GlassRow<Content: View>: View {
    let cornerRadius: CGFloat
    let content: () -> Content
    init(cornerRadius: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    content()
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                        .glassEffect(.regular.interactive(),
                                     in: .rect(cornerRadius: cornerRadius, style: .continuous))
                }
            } else {
                content()
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial).opacity(0.6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 0.7)
                    )
            }
        }
    }
}
