//
//  FeedView.swift
//  WWM
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct FeedPost: Identifiable, Hashable {
    let id: String
    let username: String
    let pfpBase64: String?
    let imageBase64: String
    let caption: String
    let address: String
    let createdAt: Date?
}

private let kChatsLastSeenKey = "chats_last_seen_at"

struct FeedView: View {
    @State private var showAuthSheet = true
    @StateObject private var userVM = CurrentUserViewModel()

    @State private var posts: [FeedPost] = []
    @State private var postsListener: ListenerRegistration?

    @State private var hasUnread = false
    @State private var chatsListener: ListenerRegistration?
    @State private var authHandle: AuthStateDidChangeListenerHandle?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(posts) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Base64ImageView(
                                    base64: post.pfpBase64,
                                    size: 36,
                                    cornerRadius: 18
                                )
                                Text(post.username.isEmpty ? "Unbekannt" : post.username)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .layoutPriority(1)
                                Spacer(minLength: 8)
                                if let ts = post.createdAt {
                                    Text(RelativeDateTimeFormatter().localizedString(for: ts, relativeTo: Date()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }

                            if let img = UIImage.fromBase64(post.imageBase64) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .clipped()
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(UIColor.tertiarySystemFill))
                                    .frame(height: 220)
                            }

                            if !post.caption.isEmpty {
                                Text(post.caption)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !post.address.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(.secondary)
                                    Text(post.address)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(UIColor.separator), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(
                            color: (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)),
                            radius: 8, x: 0, y: 4
                        )
                    }
                }
                .padding()
                .foregroundStyle(.primary)
            }
            .background(Color.clear)
        }
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: ProfileView(showAuthSheet: $showAuthSheet)) {
                    ZStack(alignment: .topTrailing) {
                        Base64ImageView(
                            base64: userVM.pfpBase64 ?? UserDefaults.standard.string(forKey: "pfpBase64"),
                            size: 28,
                            cornerRadius: 14
                        )
                        if hasUnread {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .offset(x: 3, y: -3)
                                .accessibilityLabel("Neue Nachrichten")
                        }
                    }
                }
            }
            ToolbarItem {
                NavigationLink(destination: PostView()) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color(hex: "#EF476F"))
                }
            }
        }
        .toolbarBackground(Color(hex: "#55A630"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            showAuthSheet = Auth.auth().currentUser == nil
            ensureLastSeenDefault()
            startListeningPosts()
            attachAuthListenerForUnread()
        }
        .onDisappear {
            stopListeningPosts()
            stopListeningUnreadChats()
            if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
            authHandle = nil
        }
        .task { await userVM.loadProfile() }
        .fullScreenCover(isPresented: $showAuthSheet) {
            NavigationStack { AuthenticationView(showAuthSheet: $showAuthSheet) }
        }
    }

    // MARK: - Posts

    private func startListeningPosts() {
        stopListeningPosts()
        postsListener = Firestore.firestore()
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snap, _ in
                let docs = snap?.documents ?? []
                let items: [FeedPost] = docs.compactMap { doc in
                    let d = doc.data()
                    return FeedPost(
                        id: doc.documentID,
                        username: (d["username"] as? String) ?? "",
                        pfpBase64: d["pfpData"] as? String,
                        imageBase64: (d["imageData"] as? String) ?? "",
                        caption: (d["caption"] as? String) ?? "",
                        address: (d["address"] as? String) ?? "",
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue()
                    )
                }
                self.posts = items
            }
    }

    private func stopListeningPosts() {
        postsListener?.remove()
        postsListener = nil
    }

    // MARK: - Unread Chats Badge

    private func ensureLastSeenDefault() {
        if UserDefaults.standard.object(forKey: kChatsLastSeenKey) == nil {
            UserDefaults.standard.set(0.0, forKey: kChatsLastSeenKey) // 1970
        }
    }

    private func attachAuthListenerForUnread() {
        authHandle = Auth.auth().addStateDidChangeListener { _, user in
            stopListeningUnreadChats()
            if user != nil {
                startListeningUnreadChats()
            } else {
                hasUnread = false
            }
        }
        if Auth.auth().currentUser != nil {
            startListeningUnreadChats()
        }
    }

    private func startListeningUnreadChats() {
        stopListeningUnreadChats()
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let lastSeenSeconds = UserDefaults.standard.object(forKey: kChatsLastSeenKey) as? Double
        let lastSeen = Date(timeIntervalSince1970: lastSeenSeconds ?? 0)
        let lastSeenMissing = (lastSeenSeconds == nil)

        chatsListener = Firestore.firestore()
            .collection("chats")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { snap, _ in
                let docs = snap?.documents ?? []
                var unread = false
                for doc in docs {
                    let d = doc.data()
                    let lastSender = d["lastSender"] as? String
                    let updatedAt = (d["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    if lastSender != uid {
                        if lastSeenMissing || updatedAt > lastSeen {
                            unread = true
                            break
                        }
                    }
                }
                self.hasUnread = unread
            }
    }

    private func stopListeningUnreadChats() {
        chatsListener?.remove()
        chatsListener = nil
    }
}

fileprivate extension UIImage {
    static func fromBase64(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
