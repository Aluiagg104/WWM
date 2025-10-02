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
    let pfpThumbBase64: String?
    let imagePreviewBase64: String?
    let imageInlineBase64: String?
    let hasChunks: Bool
    let caption: String
    let address: String
    let createdAt: Date?
    let strain: String
}

private enum MainTab: CaseIterable { case feed, profile }


private let CONTENT_SIDE_MARGIN: CGFloat = 20

struct FeedView: View {
    @State private var showAuthSheet = true
    @StateObject private var userVM = CurrentUserViewModel()
    @State private var posts: [FeedPost] = []
    @State private var postsListener: ListenerRegistration?
    @State private var tab: MainTab = .feed
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LiquidGlassBackground()
            Group {
                switch tab {
                case .feed:
                    feedContent
                case .profile:
                    ProfileView(showAuthSheet: $showAuthSheet)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: tab)
        }
        .navigationTitle(tab == .feed ? "Feed" : "")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            showAuthSheet = (Auth.auth().currentUser == nil)
            startListeningPosts()
        }
        .onDisappear {
            stopListeningPosts()
        }
        .task { await userVM.loadProfile() }
        .fullScreenCover(isPresented: $showAuthSheet) {
            NavigationStack { AuthenticationView(showAuthSheet: $showAuthSheet) }
        }
    }

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(posts) { post in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Base64ImageView(base64: post.pfpThumbBase64, size: 36, cornerRadius: 18)
                                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.username.isEmpty ? "Unbekannt" : post.username)
                                    .font(.headline)
                                if let ts = post.createdAt {
                                    Text(RelativeDateTimeFormatter().localizedString(for: ts, relativeTo: Date()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                        }
                        if !post.strain.isEmpty {
                            Label(post.strain, systemImage: "leaf.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.6))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        }
                        if let b64 = post.imagePreviewBase64 ?? post.imageInlineBase64,
                           let img = UIImage.fromBase64(b64) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.25), lineWidth: 0.6)
                                )
                                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(height: 220)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.25), lineWidth: 0.6)
                                )
                        }
                        if !post.caption.isEmpty {
                            Text(post.caption)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !post.address.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                Text(post.address).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(glassCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.3), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
                }
            }
            .padding(.horizontal, CONTENT_SIDE_MARGIN)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private var glassCardBackground: some ShapeStyle {
        .ultraThinMaterial
            .shadow(.inner(color: .white.opacity(0.08), radius: 1, x: 0, y: 1))
    }

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
                        pfpThumbBase64: d["pfpThumb"] as? String,
                        imagePreviewBase64: d["imagePreview"] as? String,
                        imageInlineBase64: d["imageData"] as? String,
                        hasChunks: (d["hasChunks"] as? Bool) ?? false,
                        caption: (d["caption"] as? String) ?? "",
                        address: (d["address"] as? String) ?? "",
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
                        strain: (d["strain"] as? String) ?? ""
                    )
                }
                self.posts = items
            }
    }

    private func stopListeningPosts() {
        postsListener?.remove()
        postsListener = nil
    }
}

fileprivate extension UIImage {
    static func fromBase64(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}

private struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                ? [Color.black, Color(hex: "#112318")]
                : [Color(hex: "#F2FFF7"), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            blob(color: Color(hex: "#55A630").opacity(0.28), size: 420, x: -120, y: -180, blur: 80)
            blob(color: Color(hex: "#EF476F").opacity(0.20), size: 380, x: 160, y: -140, blur: 100)
            blob(color: Color.blue.opacity(0.16), size: 460, x: 80, y: 300, blur: 120)
        }
    }

    private func blob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat, blur: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }
}
