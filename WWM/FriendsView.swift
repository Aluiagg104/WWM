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
        HStack(spacing: 12) {
            Base64ImageView(base64: friend.pfpData, size: 40, cornerRadius: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.username)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !friend.email.isEmpty {
                    Text(friend.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 0)

            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red))
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

    @Environment(\.colorScheme) private var colorScheme

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

    // iOS15-Fallback: ursprüngliche UITableView-Farbe merken
    @State private var prevTableBG: UIColor? = nil
    
    @State private var navSelection: String? = nil

    var filteredFriends: [AppUser] {
        guard !searchText.isEmpty else { return vm.friends }
        let q = searchText.lowercased()
        return vm.friends.filter { u in
            u.username.lowercased().contains(q) || u.email.lowercased().contains(q)
        }
    }

    var body: some View {
        listContent
        .navigationTitle("Deine Freunde")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .refreshable { await generateOrLoadFriendCode(force: true) }
        .background(AuroraRibbonsBackground(style: .auto)) // dynamisch mit System
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { ShowFriendsView = false } label: { Label("Schließen", systemImage: "xmark") }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showEnterCodeSheet = true } label: {
                    Label("ID eingeben", systemImage: "number")
                }
                Menu {
                    if let uid = Auth.auth().currentUser?.uid {
                        NavigationLink { QRCodeView(text: uid) } label: {
                            Label("QR – meine UID", systemImage: "qrcode")
                        }
                    }
                    if !myFriendCode.isEmpty {
                        let pureCode = normalizeFriendCode(myFriendCode)
                        NavigationLink { QRCodeView(text: pureCode) } label: {
                            Label("QR – mein Code", systemImage: "qrcode.viewfinder")
                        }
                    }
                } label: {
                    Image(systemName: "qrcode")
                }
                Button { showScanner = true } label: { Label("QR scannen", systemImage: "camera") }
            }
        }
        .toolbarBackground(.ultraThinMaterial)
        .onAppear {
            if isPreview {
                myFriendCode = "ABCD123456"
                return
            }
            guard !isPreview else { return }
            myUid = Auth.auth().currentUser?.uid ?? ""
            vm.start()
            unreadStore.start()
            Task { await generateOrLoadFriendCode(force: false) }

            if #available(iOS 16.0, *) {
                // handled by ListClearBG()
            } else {
                prevTableBG = UITableView.appearance().backgroundColor
                UITableView.appearance().backgroundColor = .clear
            }
        }
        .onDisappear {
            guard !isPreview else { return }
            vm.stop()
            unreadStore.stop()
            if #available(iOS 16.0, *) { } else {
                UITableView.appearance().backgroundColor = prevTableBG
            }
        }
        // Restlicher Code unverändert (Scanner, Alerts, Sections etc.)
        .fullScreenCover(isPresented: $showScanner) {
            ScannerScreen { raw in
                Task { @MainActor in
                    let scanned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let norm = normalizeFriendCode(scanned)

                    if looksLikeFriendCode(norm) {
                        do {
                            try await FirestoreManager.shared.addFriend(byFriendCode: norm)
                            showScanner = false
                            return
                        } catch { /* try UID next */ }
                    }

                    if let uid = extractUid(from: scanned), !uid.isEmpty {
                        await vm.addFriendFromScannedValue(uid)
                        showScanner = false
                        return
                    }

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
                        do {
                            try await FirestoreManager.shared.addFriend(byFriendCode: normalized)
                            await MainActor.run {
                                codeInput = ""; codeError = nil; showEnterCodeSheet = false
                            }
                            return
                        } catch { /* fall back to UID */ }
                    }

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

    // MARK: - Teil-Views (zerlegen = schnelleres Type-Checking)

    private var background: some View {
        AuroraRibbonsBackground().ignoresSafeArea()
    }
    
    private let rowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)

    // 2) Glas-Kartenhintergrund (wie bei deiner FriendCodeCard)
    private func glassCardBG(corner: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.6)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 0.7)
            )
    }
    
    @ViewBuilder private var listContent: some View {
        List {
            if !myFriendCode.isEmpty {
                Section {
                    FriendCodeCard(
                        code: myFriendCode,
                        isLoading: isLoadingFriendCode,
                        errorText: friendCodeError,
                        onRefresh: { Task { await generateOrLoadFriendCode(force: true) } }
                    )
                    .padding(12)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .glassCodeCardEffectWithFallback()
                }
            }
            
            // Inhalt
            if filteredFriends.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text(vm.friends.isEmpty ? "👋 Noch keine Freunde" : "Keine Treffer")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Freund per QR hinzufügen") { showScanner = true }
                                .glassButtonStyleOrFallback()
                            Button("Freundes-ID eingeben") { showEnterCodeSheet = true }
                                .glassButtonStyleOrFallback()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .padding()
                    .glassCodeCardEffectWithFallback()
                    .frame(alignment: .center)
                    .frame(width: 400)
                }
            } else {
                Section {
                    ForEach(filteredFriends, id: \.uid) { friend in
                        NavigationLink {
                            ChatView(user: friend)
                        } label: {
                            FriendRow(friend: friend, unreadCount: unreadCount(for: friend))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 70)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                        }
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { /* … */ } label: {
                                Label("Entfernen", systemImage: "trash")
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .glassEffectWithFallback()
                .listSectionSpacing(.compact)                   // kleiner Section-Abstand
                .listStyle(.plain)                              // optional: generell dichter
                .environment(\.defaultMinListRowHeight, 0)      // verhindert, dass iOS Mindesthöhe erzwingt
                .listSectionSpacing(.compact)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .listRowInsets(rowInsets)
        .scrollContentBackground(.hidden)
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

    private func extractUid(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uid = obj["uid"] as? String {
            return uid
        }
        if let comps = URLComponents(string: trimmed),
           let uid = comps.queryItems?.first(where: { $0.name.lowercased() == "uid" })?.value {
            return uid
        }
        if let r = trimmed.range(of: "uid:", options: .caseInsensitive) {
            let after = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty { return after }
        }
        if !trimmed.contains(" "), trimmed.count >= 18 {
            return trimmed
        }
        return nil
    }

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

    private func normalizeFriendCode(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
    }

    private func looksLikeFriendCode(_ s: String) -> Bool {
        let n = s.uppercased().replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "")
        guard n.count == 10 else { return false }
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return n.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Teil-Abschnitte für die List

private struct FriendCodeSection: View {
    let code: String
    let isLoading: Bool
    let errorText: String?
    let onRefresh: () -> Void

    var body: some View {
        Section {
            FriendCodeCard(code: code, isLoading: isLoading, errorText: errorText, onRefresh: onRefresh)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
        }
    }
}

private struct EmptyFriendsSection: View {
    let hasAnyFriends: Bool
    let onScan: () -> Void
    let onEnterCode: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 12) {
                Text(hasAnyFriends ? "Keine Treffer" : "👋 Noch keine Freunde")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Freund per QR hinzufügen", action: onScan)
                        .buttonStyle(.borderedProminent)
                    Button("Freundes-ID eingeben", action: onEnterCode)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }
}

private struct FriendsRowsSection: View {
    let friends: [AppUser]
    let unread: [String: Int]
    let myUid: String
    let onRemoveAsk: (AppUser) -> Void

    var body: some View {
        Section {
            ForEach(friends, id: \.uid) { friend in
                NavigationLink { ChatView(user: friend) } label: {
                    FriendRow(friend: friend, unreadCount: unreadCount(for: friend))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onRemoveAsk(friend)
                    } label: {
                        Label("Entfernen", systemImage: "person.crop.circle.badge.minus")
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = friend.uid
                    } label: { Label("UID kopieren", systemImage: "doc.on.doc") }
                    Button {
                        UIPasteboard.general.string = friend.username
                    } label: { Label("Username kopieren", systemImage: "doc.on.doc") }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.28), lineWidth: 0.7)
                        )
                )
            }
        }
    }

    private func chatIdBetween(me: String, other: String) -> String {
        me < other ? "\(me)_\(other)" : "\(other)_\(me)"
    }

    private func unreadCount(for friend: AppUser) -> Int {
        guard !myUid.isEmpty else { return 0 }
        let cid = chatIdBetween(me: myUid, other: friend.uid)
        return unread[cid] ?? 0
    }
}

// MARK: - Karten + Hintergrund + Modifiers

private struct FriendCodeCard: View {
    let code: String
    let isLoading: Bool
    let errorText: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Dein Freundes-Code")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding()
                    .glassEffectWithFallback()
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.8) }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .glassButtonStyleOrFallback()
            }
            

            HStack(spacing: 12) {
                Text(formatFriendCode(code))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .padding(.vertical, 4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding()
                    .glassEffectWithFallback()

                Spacer().frame(width: 0)
                
                Button {
                    guard !code.isEmpty else { return }
                    UIPasteboard.general.string = code
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.vertical, -5)
                        .padding(.horizontal, -5)
                }
                .controlSize(.large)
                .glassButtonStyleOrFallback()
                
                if !code.isEmpty {
                    ShareLink(items: [shareTextForCode(code)]) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.vertical, 5)
                            .padding(.horizontal, 5)
                    }
                    .glassButtonStyleOrFallback()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 0.7)
            )

            if let errorText, !errorText.isEmpty {
                Text(errorText)
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
    }

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
}

/// Sanfter Aurora-Look (blau/türkis/violett), bewusst **anders** als der Feed/Profile-Hintergrund.
private struct AuroraRibbonsBackground: View {
    enum Style { case auto, dark, light }
    var style: Style = .auto

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { style == .dark || (style == .auto && colorScheme == .dark) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isDark
                ? [Color(hex: "#0A0F1E"), Color(hex: "#0B1327")]
                : [Color(hex: "#EAF3FF"), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // leicht gedämpfte, dunkle Intensitäten im Dark-Case
            ribbon(.cyan.opacity(isDark ? 0.22 : 0.35), .blue.opacity(isDark ? 0.06 : 0.10), w: 900, h: 260, x: 0,   y: -280, rot: -18, blur: 42)
            ribbon(.purple.opacity(isDark ? 0.18 : 0.30), .clear,                               w: 780, h: 220, x: 60,  y: 40,   rot: 12,  blur: 36)
            ribbon(.mint.opacity(isDark ? 0.20 : 0.28), .teal.opacity(isDark ? 0.06 : 0.10),   w: 900, h: 240, x: -40, y: 360,  rot: -10, blur: 46)

            orb(.cyan.opacity(isDark ? 0.18 : 0.25),   size: 420, x: -160, y: -180, blur: 90)
            orb(.purple.opacity(isDark ? 0.16 : 0.22), size: 360, x: 160,  y: -120, blur: 95)
            orb(.indigo.opacity(isDark ? 0.14 : 0.18), size: 520, x: 100,  y: 340,  blur: 120)
        }
        .ignoresSafeArea()
    }

    private func ribbon(_ c1: Color, _ c2: Color, w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, rot: Double, blur: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: w, height: h)
            .rotationEffect(.degrees(rot))
            .offset(x: x, y: y)
            .blur(radius: blur)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private func orb(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, blur: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(x: x, y: y)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

/// Versteckt den Standard-Listenhintergrund (iOS16+) mit Fallback für iOS15.
private struct ListClearBG: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        } else {
            content
                .background(Color.clear)
        }
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

    // Formatierungshilfe für die Anzeige des eigenen Codes
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

private extension View {
    @ViewBuilder
    func glassButtonStyleOrFallback() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderedProminent) // oder .bordered, wie du willst
        }
    }
    
    @ViewBuilder
    func glassEffectWithFallback() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect()
        } else {
            self
        }
    }
    
    @ViewBuilder
    func glassCodeCardEffectWithFallback() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
        } else {
            self
        }
    }
    
    @ViewBuilder
    func glassCardBackground(cornerRadius: CGFloat = 12) -> some View {
        if #available(iOS 18.0, *) {
            self.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .glassEffectWithFallback()
            }
        } else {
            // Fallback: Material in die Shape „einschneiden“
            self.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView(
            showAuthSheet: .constant(false),
            ShowFriendsView: .constant(true)
        )
    }
}
private var isPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}
