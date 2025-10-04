import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit
import Foundation

private var isRunningInPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

struct FeedPost: Identifiable, Hashable {
    let id: String
    let authorUid: String
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
                case .feed:    feedContent
                case .profile: ProfileView()
                }
            }
            .padding(.horizontal, 12)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: tab)
        }
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if isRunningInPreview {
                showAuthSheet = false
                posts = FeedView.samplePosts
            } else {
                showAuthSheet = (Auth.auth().currentUser == nil)
                startListeningPosts()
                userVM.startAuthListener()   // Live auf eigenen User
            }
        }
        .onDisappear {
            if !isRunningInPreview {
                stopListeningPosts()
                userVM.stopAuthListener()
            }
        }
        .fullScreenCover(isPresented: $showAuthSheet) {
            NavigationStack { AuthenticationView() }
        }
    }

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(posts) { post in
                    FeedPostCard(
                        post: post,
                        currentUserPfp: userVM.pfpBase64,
                        currentUsername: userVM.username
                    )
                    .id(post.id) // stabil pro Post
                }
            }
            .padding(.horizontal, CONTENT_SIDE_MARGIN)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Firestore: Posts

    private func startListeningPosts() {
        stopListeningPosts()
        postsListener = Firestore.firestore()
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener(includeMetadataChanges: true) { snap, _ in
                let docs = snap?.documents ?? []
                let items: [FeedPost] = docs.compactMap { doc in
                    let d = doc.data()
                    return FeedPost(
                        id: doc.documentID,
                        // ⬅️ WICHTIG: Fallback auf "uid" (so heißen deine Rules/Docs)
                        authorUid: (d["authorUid"] as? String) ?? (d["uid"] as? String) ?? "",
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
                DispatchQueue.main.async {
                    self.posts = items
                }
            }
    }

    private func stopListeningPosts() {
        postsListener?.remove()
        postsListener = nil
    }
}

// MARK: - Card (mit eigenem Live-Listener pro Autor)

private struct FeedPostCard: View {
    let post: FeedPost
    let currentUserPfp: String?
    let currentUsername: String?

    @State private var liveUsername: String?
    @State private var livePfp: String?
    @State private var authorListener: ListenerRegistration?

    private let corner: CGFloat = 18
    private static let rdf: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    // Live-Priorität: livePfp > (eigener aktueller PFP bei eigenem Post) > gespeicherter pfpThumb
    private var effectivePfp: String? {
        if let livePfp, !livePfp.isEmpty { return livePfp }
        if post.username == currentUsername, let me = currentUserPfp, !me.isEmpty { return me }
        return post.pfpThumbBase64
    }

    // Live-Name (fallback: gespeicherter Name im Post)
    private var effectiveUsername: String {
        let candidate = (liveUsername?.isEmpty == false ? liveUsername! : post.username)
        return candidate.isEmpty ? "Unbekannt" : candidate
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            header
            strainPill
            postImage
            caption
            address
        }
        .padding(14)
        .onAppear { attachAuthorListener() }
        .onDisappear { detachAuthorListener() }
        // Falls sich der Author-Uid des Posts ändert, Listener neu setzen
        .onChange(of: post.authorUid) { _, _ in
            detachAuthorListener()
            attachAuthorListener()
        }

        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                content.glassEffect(.regular.interactive(),
                                    in: .rect(cornerRadius: 12, style: .continuous))
            }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial).opacity(0.55)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 0.7)
                )
        }
    }

    private func attachAuthorListener() {
        guard !post.authorUid.isEmpty, authorListener == nil else { return }
        let ref = Firestore.firestore().collection("users").document(post.authorUid)

        // Live-Listener (Cache + Server)
        authorListener = ref.addSnapshotListener(includeMetadataChanges: true) { snap, err in
            if let err = err {
                print("❌ users/\(post.authorUid) listen error:", err)
                return
            }
            guard let data = snap?.data() else { return }
            let name = data["username"] as? String
            let pfp  = data["pfpData"] as? String
            DispatchQueue.main.async {
                self.liveUsername = name
                self.livePfp = pfp
            }
        }

        // Einmal explizit vom Server (Cache durchstoßen)
        ref.getDocument(source: .server) { snap, _ in
            guard let data = snap?.data() else { return }
            let name = data["username"] as? String
            let pfp  = data["pfpData"] as? String
            DispatchQueue.main.async {
                self.liveUsername = name
                self.livePfp = pfp
            }
        }
    }

    private func detachAuthorListener() {
        authorListener?.remove()
        authorListener = nil
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let b64 = effectivePfp, let img = UIImage.fromBase64(b64) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
            } else {
                Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(effectiveUsername)
                    .font(.headline)
                if let ts = post.createdAt {
                    Text(Self.rdf.localizedString(for: ts, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder private var strainPill: some View {
        if !post.strain.isEmpty {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    Label(post.strain, systemImage: "leaf.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }
            } else {
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
        }
    }

    @ViewBuilder private var postImage: some View {
        if let b64 = post.imagePreviewBase64 ?? post.imageInlineBase64,
           let img = UIImage.fromBase64(b64) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(img.size, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: corner).stroke(.white.opacity(0.25), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
        } else {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: corner).stroke(.white.opacity(0.25), lineWidth: 0.6))
        }
    }

    @ViewBuilder private var caption: some View {
        if !post.caption.isEmpty {
            Text(post.caption)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var address: some View {
        if !post.address.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(post.address).fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Background

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

fileprivate extension UIImage {
    static func fromBase64(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}

#Preview {
    FeedView()
}

#if DEBUG
extension FeedView {
    static let samplePosts: [FeedPost] = [
        FeedPost(
            id: "1",
            authorUid: "preview-olivia",
            username: "Olivia",
            pfpThumbBase64: nil,
            imagePreviewBase64: sampleBase64Image(width: 900, height: 600),
            imageInlineBase64: nil,
            hasChunks: false,
            caption: "Sonnenuntergang am Kanal 🌇",
            address: "Berlin, Kreuzberg",
            createdAt: Date().addingTimeInterval(-3600),
            strain: "Blue Haze"
        ),
        FeedPost(
            id: "2",
            authorUid: "preview-max",
            username: "Max",
            pfpThumbBase64: nil,
            imagePreviewBase64: nil,
            imageInlineBase64: nil,
            hasChunks: false,
            caption: "Erster Post! 🎉",
            address: "Hamburg",
            createdAt: Date().addingTimeInterval(-86_400),
            strain: ""
        )
    ]
}

private func sampleBase64Image(width: Int, height: Int) -> String {
    let size = CGSize(width: width, height: height)
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { ctx in
        let colors = [UIColor.systemPink.cgColor, UIColor.systemTeal.cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0,1])!
        ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
    }
    return (img.jpegData(compressionQuality: 0.85) ?? Data()).base64EncodedString()
}
#endif
