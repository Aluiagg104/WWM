//
//  FriendsView.swift
//  WWM
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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

            // 1) nicht sich selbst adden
            guard myUid != otherUid else {
                print("Scan ist die eigene UID – wird ignoriert.")
                return
            }

            // 2) existiert der andere wirklich in /users?
            let exists = try await Firestore.firestore()
                .collection("users")
                .document(otherUid)
                .getDocument()
                .exists

            guard exists else {
                print("Kein User-Dokument für \(otherUid) – QR ungültig?")
                return
            }

            try await FirestoreManager.shared.addFriend(between: myUid, and: otherUid)
            print("Freundschaft angelegt \(myUid) <-> \(otherUid)")
        } catch {
            print("add friend failed:", error.localizedDescription)
        }
    }

    func removeFriend(uid otherUid: String) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FirestoreManager.shared.removeFriend(between: myUid, and: otherUid)
        } catch {
            print("remove friend failed:", error.localizedDescription)
        }
    }
}

struct FriendRow: View {
    let friend: AppUser

    var body: some View {
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
    }
}

struct FriendsView: View {
    @Binding var showAuthSheet: Bool
    @StateObject private var vm = FriendsViewModel()
    @State private var showScanner = false
    @Binding var ShowFriendsView: Bool

    @State private var scanError: String?
    
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
                    NavigationLink {
                        ChatView(user: friend)
                    } label: {
                        FriendRow(friend: friend)
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
                if let uid = Auth.auth().currentUser?.uid {
                    NavigationLink {
                        QRCodeView(text: uid)
                    } label: {
                        Image(systemName: "qrcode")
                    }
                } else {
                    // optional: disabled/hidden
                    Image(systemName: "qrcode").opacity(0.4)
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerScreen { raw in
                Task { @MainActor in
                    let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)

                    // optional: akzeptiere auch QR, die eine URL oder ein "uid:XYZ" enthalten
                    let uid = extractUid(from: code)

                    guard let uid = uid, !uid.isEmpty else {
                        scanError = "Ungültiger QR-Code."
                        showScanner = false
                        return
                    }

                    await vm.addFriendFromScannedValue(uid)   // wir geben wirklich nur die UID weiter
                    showScanner = false
                }
            }
        }
        .alert("Fehler", isPresented: .constant(scanError != nil)) {
            Button("OK") { scanError = nil }
        } message: {
            Text(scanError ?? "")
        }
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
    
    private func extractUid(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Reiner UID-String?
        if !trimmed.contains(" ") && !trimmed.contains("\n") && !trimmed.contains("://") && !trimmed.contains("{") {
            return trimmed
        }

        // 2) "uid:XYZ"
        if let range = trimmed.range(of: "uid:", options: .caseInsensitive) {
            let uid = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return uid
        }

        // 3) URL mit ?uid=XYZ
        if let comps = URLComponents(string: trimmed),
           let uid = comps.queryItems?.first(where: { $0.name.lowercased() == "uid" })?.value {
            return uid
        }

        // 4) kleine JSON-Variante {"uid":"..."}
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uid = obj["uid"] as? String {
            return uid
        }

        return nil
    }
}
