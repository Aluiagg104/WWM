//
//  FriendsView.swift
//  WWM
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private let kChatsLastSeenKey = "chats_last_seen_at"

@MainActor
final class UnreadPerChatStore: ObservableObject {
    @Published var counts: [String: Int] = [:]

    private var chatsListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var authHandle: AuthStateDidChangeListenerHandle?

    func start() {
        stop()
        if UserDefaults.standard.object(forKey: kChatsLastSeenKey) == nil {
            UserDefaults.standard.set(0.0, forKey: kChatsLastSeenKey)
        }

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.rebuild(for: user?.uid)
        }
        rebuild(for: Auth.auth().currentUser?.uid)
    }

    func stop() {
        chatsListener?.remove()
        chatsListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
        authHandle = nil
        counts.removeAll()
    }

    private func rebuild(for uid: String?) {
        chatsListener?.remove(); chatsListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        counts.removeAll()

        guard let uid else { return }

        let lastSeenSeconds = UserDefaults.standard.object(forKey: kChatsLastSeenKey) as? Double ?? 0
        let lastSeen = Date(timeIntervalSince1970: lastSeenSeconds)

        chatsListener = Firestore.firestore()
            .collection("chats")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let docs = snap?.documents ?? []
                let liveIds = Set(docs.map { $0.documentID })

                for (cid, l) in self.messageListeners where !liveIds.contains(cid) {
                    l.remove()
                    self.messageListeners.removeValue(forKey: cid)
                    self.counts[cid] = 0
                }

                for doc in docs {
                    let cid = doc.documentID
                    if self.messageListeners[cid] == nil {
                        self.messageListeners[cid] = Firestore.firestore()
                            .collection("chats").document(cid)
                            .collection("messages")
                            .whereField("createdAt", isGreaterThan: lastSeen)
                            .addSnapshotListener { [weak self] msgSnap, _ in
                                guard let self else { return }
                                let all = msgSnap?.documents ?? []
                                let count = all.reduce(0) { acc, d in
                                    let sender = d["senderId"] as? String
                                    return acc + ((sender == uid) ? 0 : 1)
                                }
                                Task { @MainActor in self.counts[cid] = count }
                            }
                    }
                }
            }
    }
}

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

    func stop() { listener?.remove(); listener = nil }

    func addFriendFromScannedValue(_ value: String, isValueUid: Bool = true) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        do {
            let otherUid: String
            if isValueUid {
                otherUid = value
            } else {
                guard let user = try await FirestoreManager.shared.fetchUser(byUsername: value) else { return }
                otherUid = user.uid
            }
            guard myUid != otherUid else { return }
            let exists = try await Firestore.firestore().collection("users").document(otherUid).getDocument().exists
            guard exists else { return }
            try await FirestoreManager.shared.addFriend(between: myUid, and: otherUid)
        } catch {
            print("add friend failed:", error.localizedDescription)
        }
    }

    func removeFriend(uid otherUid: String) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        do { try await FirestoreManager.shared.removeFriend(between: myUid, and: otherUid) }
        catch { print("remove friend failed:", error.localizedDescription) }
    }
}

struct FriendRow: View {
    let friend: AppUser
    let unreadCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                Base64ImageView(base64: friend.pfpData, size: 40, cornerRadius: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.username).font(.headline)
                    if !friend.email.isEmpty {
                        Text(friend.email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("\(unreadCount) neue Nachrichten")
            }
        }
    }
}

struct FriendsView: View {
    @Binding var showAuthSheet: Bool
    @Binding var ShowFriendsView: Bool

    @StateObject private var vm = FriendsViewModel()
    @StateObject private var unreadStore = UnreadPerChatStore()

    @State private var showScanner = false
    @State private var scanError: String?
    @State private var pendingDeletion: AppUser? = nil
    @State private var showConfirmDelete = false

    // eigene UID puffern -> weniger komplexe Ausdrücke im ViewBuilder
    @State private var myUid: String = Auth.auth().currentUser?.uid ?? ""

    var body: some View {
        List {
            if vm.friends.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("👋 Noch keine Freunde").foregroundStyle(.secondary)
                        Button("Freund per QR hinzufügen") { showScanner = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(vm.friends, id: \.uid) { friend in
                    NavigationLink { ChatView(user: friend) } label: {
                        FriendRow(friend: friend, unreadCount: unreadCount(for: friend))
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
                Button { ShowFriendsView = false } label: { Label("schließen", systemImage: "xmark") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showScanner = true } label: { Label("QR scannen", systemImage: "camera") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let uid = Auth.auth().currentUser?.uid {
                    NavigationLink { QRCodeView(text: uid) } label: {
                        Image(systemName: "qrcode")   // <-- FIX
                    }
                } else {
                    Image(systemName: "qrcode").opacity(0.4)
                }
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
        .fullScreenCover(isPresented: $showScanner) {
            ScannerScreen { raw in
                Task { @MainActor in
                    let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let uid = extractUid(from: code)
                    guard let uid, !uid.isEmpty else {
                        scanError = "Ungültiger QR-Code."
                        showScanner = false
                        return
                    }
                    await vm.addFriendFromScannedValue(uid)
                    showScanner = false
                }
            }
        }
        .alert("Fehler", isPresented: .constant(scanError != nil)) {
            Button("OK") { scanError = nil }
        } message: { Text(scanError ?? "") }
        .alert("Freund entfernen?", isPresented: $showConfirmDelete, presenting: pendingDeletion) { friend in
            Button("Entfernen", role: .destructive) {
                Task {
                    await vm.removeFriend(uid: friend.uid)
                    pendingDeletion = nil
                }
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { friend in
            Text("Möchtest du \(friend.username) wirklich aus deiner Freundesliste entfernen?")
        }
    }

    // MARK: - Helpers

    private func unreadCount(for friend: AppUser) -> Int {
        guard !myUid.isEmpty else { return 0 }
        let cid = chatIdBetween(me: myUid, other: friend.uid)
        return unreadStore.counts[cid] ?? 0
    }

    private func chatIdBetween(me: String, other: String) -> String {
        return me < other ? "\(me)_\(other)" : "\(other)_\(me)"
    }

    private func extractUid(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(" ") && !trimmed.contains("\n") && !trimmed.contains("://") && !trimmed.contains("{") { return trimmed }
        if let r = trimmed.range(of: "uid:", options: .caseInsensitive) {
            return trimmed[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let comps = URLComponents(string: trimmed),
           let uid = comps.queryItems?.first(where: { $0.name.lowercased() == "uid" })?.value { return uid }
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uid = obj["uid"] as? String { return uid }
        return nil
    }
}
