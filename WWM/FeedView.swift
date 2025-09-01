//
//  FeedView.swift
//  WWM
//
//  Created by F on 20.08.25.
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

struct FeedView: View {
    @State private var showAuthSheet = true
    @StateObject private var userVM = CurrentUserViewModel()

    @State private var posts: [FeedPost] = []
    @State private var listener: ListenerRegistration?

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
                                    .lineLimit(nil)
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
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !post.address.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(.secondary)
                                    Text(post.address)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(nil)
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
                    Base64ImageView(
                        base64: userVM.pfpBase64 ?? UserDefaults.standard.string(forKey: "pfpBase64"),
                        size: 28,
                        cornerRadius: 14
                    )
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
            startListeningPosts()
        }
        .onDisappear {
            stopListeningPosts()
        }
        .task {
            await userVM.loadProfile()
        }
        .fullScreenCover(isPresented: $showAuthSheet) {
            NavigationStack { AuthenticationView(showAuthSheet: $showAuthSheet) }
        }
    }

    private func startListeningPosts() {
        stopListeningPosts()
        listener = Firestore.firestore()
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
        listener?.remove()
        listener = nil
    }
}

fileprivate extension UIImage {
    static func fromBase64(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
