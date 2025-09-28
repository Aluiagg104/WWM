//
//  FriendsView.swift
//  WWM
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

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

    // QR
    @State private var showScanner = false
    @State private var scanError: String?

    // Entfernen
    @State private var pendingDeletion: AppUser? = nil
    @State private var showConfirmDelete = false

    // eigene UID
    @State private var myUid: String = Auth.auth().currentUser?.uid ?? ""

    // Freundes-ID
    @State private var myFriendCode: String = ""
    @State private var isLoadingFriendCode = false
    @State private var friendCodeError: String?

    // ID-Eingabe
    @State private var showEnterCodeSheet = false
    @State private var codeInput: String = ""
    @State private var codeError: String?

    // Suche
    @State private var searchText = ""

    var filteredFriends: [AppUser] {
        guard !searchText.isEmpty else { return vm.friends }
        let q = searchText.lowercased()
        return vm.friends.filter { u in
            u.username.lowercased().contains(q) || u.email.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            // Dein Freundes-Code – groß, kopierbar, neu laden
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("Dein Freundes-Code")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isLoadingFriendCode { ProgressView().scaleEffect(0.8) }
                        Button { Task { await generateOrLoadFriendCode(force: true) } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Code neu laden/erstellen")
                        .disabled(isLoadingFriendCode || Auth.auth().currentUser == nil)
                    }

                    HStack(spacing: 12) {
                        Text(formatFriendCode(myFriendCode))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .padding(.vertical, 4)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            guard !myFriendCode.isEmpty else { return }
                            UIPasteboard.general.string = myFriendCode
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: { Image(systemName: "doc.on.doc") }

                        if !myFriendCode.isEmpty {
                            ShareLink(items: [shareTextForCode(myFriendCode)]) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(UIColor.separator), lineWidth: 0.5))

                    if let friendCodeError {
                        Text(friendCodeError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Teile diesen Code oder nutze den QR-Code – andere können dich so als Freund hinzufügen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Freunde-Liste / Empty State
            if filteredFriends.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text(vm.friends.isEmpty ? "👋 Noch keine Freunde" : "Keine Treffer")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Freund per QR hinzufügen") { showScanner = true }
                                .buttonStyle(.borderedProminent)
                            Button("Freundes-ID eingeben") { showEnterCodeSheet = true }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(filteredFriends, id: \.uid) { friend in
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
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = friend.uid
                        } label: {
                            Label("UID kopieren", systemImage: "doc.on.doc")
                        }
                        Button {
                            UIPasteboard.general.string = friend.username
                        } label: {
                            Label("Username kopieren", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
        .navigationTitle("Deine Freunde")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .refreshable { await generateOrLoadFriendCode(force: true) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { ShowFriendsView = false } label: { Label("Schließen", systemImage: "xmark") }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                // ID eingeben
                Button { showEnterCodeSheet = true } label: {
                    Label("ID eingeben", systemImage: "number")
                }

                // QR: UID oder Kurz-ID
                Menu {
                    if let uid = Auth.auth().currentUser?.uid {
                        NavigationLink { QRCodeView(text: uid) } label: {
                            Label("QR – meine UID", systemImage: "qrcode")
                        }
                    }
                    if !myFriendCode.isEmpty {
                        // ⬇️ QR nur mit der reinen Kurz-ID (ohne # / Leerzeichen)
                        let pureCode = normalizeFriendCode(myFriendCode)
                        NavigationLink { QRCodeView(text: pureCode) } label: {
                            Label("QR – mein Code", systemImage: "qrcode.viewfinder")
                        }
                    }
                } label: {
                    Image(systemName: "qrcode")
                }

                // Direkt scannen
                Button { showScanner = true } label: { Label("QR scannen", systemImage: "camera") }
            }
        }
        .onAppear {
            myUid = Auth.auth().currentUser?.uid ?? ""
            vm.start()
            unreadStore.start()
            Task { await generateOrLoadFriendCode(force: false) }
        }
        .onDisappear {
            vm.stop()
            unreadStore.stop()
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerScreen { raw in
                Task { @MainActor in
                    let scanned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let norm = normalizeFriendCode(scanned)

                    // 1) ZUERST: Kurz-ID (z. B. ABCD234567)
                    if looksLikeFriendCode(norm) {
                        do {
                            try await FirestoreManager.shared.addFriend(byFriendCode: norm)
                            showScanner = false
                            return
                        } catch {
                            // fällt weiter zu UID
                        }
                    }

                    // 2) Danach: UID / URL / JSON erkennen
                    if let uid = extractUid(from: scanned), !uid.isEmpty {
                        await vm.addFriendFromScannedValue(uid)
                        showScanner = false
                        return
                    }

                    // 3) Fehler
                    scanError = "Ungültiger QR-Inhalt."
                    showScanner = false
                }
            }
        }
        .sheet(isPresented: $showEnterCodeSheet) {
            EnterCodeSheet(myCode: myFriendCode,
                           codeInput: $codeInput,
                           errorText: $codeError) { normalized in
                Task {
                    if looksLikeFriendCode(normalized) {
                        // klarer Kurz-ID-Fall
                        do {
                            try await FirestoreManager.shared.addFriend(byFriendCode: normalized)
                            await MainActor.run {
                                codeInput = ""; codeError = nil; showEnterCodeSheet = false
                            }
                            return
                        } catch {
                            // fällt auf UID-Check
                        }
                    }

                    // UID-Check
                    do {
                        guard let myUid = Auth.auth().currentUser?.uid else { return }
                        let exists = try await Firestore.firestore().collection("users").document(normalized).getDocument().exists
                        if exists, normalized != myUid {
                            try await FirestoreManager.shared.addFriend(between: myUid, and: normalized)
                            await MainActor.run {
                                codeInput = ""; codeError = nil; showEnterCodeSheet = false
                            }
                            return
                        }
                    } catch { /* ignore */ }

                    await MainActor.run {
                        codeError = "Code/UID nicht gefunden oder bereits befreundet."
                    }
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

    // MARK: - Friend-Code laden/erstellen

    private func generateOrLoadFriendCode(force: Bool) async {
        guard Auth.auth().currentUser != nil else { return }
        if isLoadingFriendCode { return }
        isLoadingFriendCode = true
        friendCodeError = nil
        defer { isLoadingFriendCode = false }

        do {
            if !force, !myFriendCode.isEmpty { return }
            let code = try await FirestoreManager.shared.ensureFriendCodeExists()
            await MainActor.run { self.myFriendCode = code }
        } catch {
            await MainActor.run {
                self.friendCodeError = "Code konnte nicht erzeugt werden. Prüfe Internet/Rules."
            }
        }
    }

    // MARK: - Helpers

    private func unreadCount(for friend: AppUser) -> Int {
        guard !myUid.isEmpty else { return 0 }
        let cid = chatIdBetween(me: myUid, other: friend.uid)
        return unreadStore.counts[cid] ?? 0
    }

    private func chatIdBetween(me: String, other: String) -> String {
        me < other ? "\(me)_\(other)" : "\(other)_\(me)"
    }

    /// Erkennung für UID in plain / URL / JSON
    private func extractUid(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSON {"uid":"..."}
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uid = obj["uid"] as? String {
            return uid
        }

        // URL …?uid=...
        if let comps = URLComponents(string: trimmed),
           let uid = comps.queryItems?.first(where: { $0.name.lowercased() == "uid" })?.value {
            return uid
        }

        // Präfix "uid: ..."
        if let r = trimmed.range(of: "uid:", options: .caseInsensitive) {
            let after = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty { return after }
        }

        // Plain UID Heuristik: lang genug (z.B. 20–36), keine Leerzeichen
        if !trimmed.contains(" "),
           trimmed.count >= 18 {
            return trimmed
        }

        return nil
    }

    /// Schönes Label für Anzeige: #XXXX XXXX XX
    private func formatFriendCode(_ raw: String) -> String {
        let code = raw.uppercased().replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "")
        guard !code.isEmpty else { return "–" }
        let chars = Array(code)
        var parts: [String] = []
        let cuts = [0..<min(4, chars.count),
                    min(4, chars.count)..<min(8, chars.count),
                    min(8, chars.count)..<min(10, chars.count)]
        for r in cuts where r.lowerBound < r.upperBound { parts.append(String(chars[r])) }
        return "#"+parts.joined(separator: " ")
    }

    private func shareTextForCode(_ code: String) -> String {
        "Füg mich als Freund hinzu mit meiner ID: \(formatFriendCode(code))"
    }

    /// Rohcode ohne #/Spaces in Großbuchstaben
    private func normalizeFriendCode(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
    }

    /// Erkanntes Kurz-ID-Pattern: exakt 10 Zeichen aus unserem Alphabet
    private func looksLikeFriendCode(_ s: String) -> Bool {
        let n = s.uppercased().replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "")
        guard n.count == 10 else { return false }
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return n.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - ID-Eingabe Sheet

private struct EnterCodeSheet: View {
    let myCode: String
    @Binding var codeInput: String
    @Binding var errorText: String?
    var onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    // Vorschau für Kurz-ID hübsch formatiert
    private var formattedPreview: String {
        let normalized = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        let chars = Array(normalized)
        guard !chars.isEmpty else { return "–" }
        var parts: [String] = []
        let cuts = [0..<min(4, chars.count),
                    min(4, chars.count)..<min(8, chars.count),
                    min(8, chars.count)..<min(10, chars.count)]
        for r in cuts where r.lowerBound < r.upperBound { parts.append(String(chars[r])) }
        return "#"+parts.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Freundes-ID oder UID eingeben")) {
                    HStack(spacing: 8) {
                        TextField("#XXXXXXXXXX oder UID", text: $codeInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(.system(.body, design: .monospaced))
                        Button {
                            if let s = UIPasteboard.general.string, !s.isEmpty {
                                codeInput = s
                            }
                        } label: { Image(systemName: "doc.on.clipboard") }
                        .help("Aus Zwischenablage einfügen")
                        if !codeInput.isEmpty {
                            Button { codeInput = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .foregroundStyle(.secondary)
                                .buttonStyle(.plain)
                                .help("Feld leeren")
                        }
                    }
                    Text("Wird als Code erkannt: \(formattedPreview)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let e = errorText { Text(e).foregroundColor(.red) }
                }

                // Dein eigener Code darunter
                Section {
                    HStack {
                        Text("Dein Code:").foregroundStyle(.secondary)
                        Spacer()
                        Text(format(myCode))
                            .font(.system(.body, design: .monospaced))
                            .bold()
                        Button {
                            UIPasteboard.general.string = myCode
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        let normalized = codeInput
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: " ", with: "")
                            .replacingOccurrences(of: "#", with: "")
                            .uppercased()
                        guard !normalized.isEmpty else { return }
                        onSubmit(normalized)
                    } label: {
                        Label("Freund hinzufügen", systemImage: "person.badge.plus")
                    }
                    .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("ID eingeben")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
        }
    }

    private func format(_ raw: String) -> String {
        let code = raw.uppercased().replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "")
        guard !code.isEmpty else { return "–" }
        let chars = Array(code)
        var parts: [String] = []
        let cuts = [0..<min(4, chars.count),
                    min(4, chars.count)..<min(8, chars.count),
                    min(8, chars.count)..<min(10, chars.count)]
        for r in cuts where r.lowerBound < r.upperBound { parts.append(String(chars[r])) }
        return "#"+parts.joined(separator: " ")
    }
}
