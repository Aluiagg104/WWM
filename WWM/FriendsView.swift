//
//  FriendsView.swift
//  WWM
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore // für ListenerRegistration

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var friends: [AppUser] = []
    private var listener: ListenerRegistration?

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener = FirestoreManager.shared.listenFriends(of: uid) { [weak self] ids in
            Task { @MainActor in
                do {
                    let users = try await FirestoreManager.shared.fetchUsers(byUIDs: ids)
                    self?.friends = users
                } catch {
                    print("friends load error:", error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    /// QR enthält die UID des anderen Users
    func addFriendFromScannedValue(_ value: String) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FirestoreManager.shared.addFriend(between: myUid, and: value)
        } catch {
            print("add friend failed:", error.localizedDescription)
        }
    }

    /// Freundschaft beidseitig entfernen
    func removeFriend(uid otherUid: String) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FirestoreManager.shared.removeFriend(between: myUid, and: otherUid)
        } catch {
            print("remove friend failed:", error.localizedDescription)
        }
    }
}

struct FriendsView: View {
    @Binding var showAuthSheet: Bool
    @StateObject private var vm = FriendsViewModel()
    @State private var showScanner = false
    @Binding var ShowFriendsView: Bool

    // Für den Bestätigungs-Dialog
    @State private var pendingDeletion: AppUser? = nil
    @State private var showConfirmDelete = false

    var body: some View {
        List {
            if vm.friends.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("👋 Noch keine Freunde")
                            .foregroundStyle(.secondary)
                        Button("Freund per QR hinzufügen") { showScanner = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(vm.friends, id: \.uid) { friend in
                    HStack(spacing: 12) {
                        Base64ImageView(base64: friend.pfpData, size: 40, cornerRadius: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.username).font(.headline)
                            if !friend.email.isEmpty {
                                Text(friend.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            pendingDeletion = friend
                            showConfirmDelete = true
                        } label: {
                            Label("Entfernen", systemImage: "person.crop.circle.badge.minus")
                        }
                    }
                }
            }
        }
        .navigationTitle("Deine Freunde")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { ShowFriendsView = false } label: {
                    Label("schließen", systemImage: "xmark")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button { showScanner = true } label: {
                    Label("QR scannen", systemImage: "camera")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    // QR zeigt die EIGENE UID
                    QRCodeView(text: Auth.auth().currentUser?.uid ?? "NO_UID")
                } label: {
                    Image(systemName: "qrcode")
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerScreen { code in
                Task { await vm.addFriendFromScannedValue(code) }
            }
        }
        // Bestätigungs-Alert
        .alert("Freund entfernen?", isPresented: $showConfirmDelete, presenting: pendingDeletion) { friend in
            Button("Entfernen", role: .destructive) {
                Task {
                    await vm.removeFriend(uid: friend.uid)
                    pendingDeletion = nil
                }
            }
            Button("Abbrechen", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { friend in
            Text("Möchtest du \(friend.username) wirklich aus deiner Freundesliste entfernen?")
        }
    }
}
