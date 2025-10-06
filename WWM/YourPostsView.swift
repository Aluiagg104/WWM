import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

private var isRunningInPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

struct YourPost: Identifiable, Hashable {
    let id: String
    let authorUid: String
    let username: String
    let pfpBase64: String?
    let imageBase64: String
    let caption: String
    let address: String
    let createdAt: Date?
}

struct YourPostsView: View {
    @State private var errorText: String?
    @State private var posts: [YourPost] = []
    @State private var listener: ListenerRegistration?
    @State private var postToDelete: YourPost?
    @State private var showDeleteAlert = false

    private let rdf: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            backgroundLayer
            Group {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer { content }
                } else {
                    content
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .navigationTitle("Deine Beiträge")
        .onAppear { startListening() }
        .onDisappear { stopListening() }
        .alert("Beitrag löschen?", isPresented: $showDeleteAlert, presenting: postToDelete) { post in
            Button("Löschen", role: .destructive) {
                Task { await deletePost(post) }
            }
            Button("Abbrechen", role: .cancel) { postToDelete = nil }
        } message: { _ in
            Text("Dieser Vorgang kann nicht rückgängig gemacht werden.")
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.13, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            Circle().fill(Color(red: 0.33, green: 0.77, blue: 0.39).opacity(0.28)).frame(width: 560, height: 560).blur(radius: 120).offset(x: -180, y: -320).allowsHitTesting(false)
            Circle().fill(Color(red: 0.96, green: 0.28, blue: 0.43).opacity(0.20)).frame(width: 420, height: 420).blur(radius: 120).offset(x: 200, y: -140).allowsHitTesting(false)
            Circle().fill(Color.blue.opacity(0.18)).frame(width: 600, height: 600).blur(radius: 160).offset(x: 100, y: 360).allowsHitTesting(false)
        }
    }

    private var content: some View {
        ScrollView {
            if let err = errorText {
                Text(err)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .lgCapsule()
                    .padding(.top, 8)
            }

            if posts.isEmpty {
                VStack(spacing: 12) {
                    Text("Noch keine eigenen Beiträge")
                        .foregroundColor(.primary)
                        .font(.headline)
                    Text("Erstelle einen Post, um ihn hier zu sehen.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .padding(16)
                .lgRect(16)
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(posts) { post in
                        YourPostRow(post: post, rdf: rdf) { toDelete in
                            postToDelete = toDelete
                            showDeleteAlert = true
                        }
                    }
                    .frame(maxWidth: 400)
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
    }

    private func startListening() {
        stopListening()
        if isRunningInPreview || Auth.auth().currentUser == nil {
            let items = YourPostsView.samplePosts
            let sorted = items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            DispatchQueue.main.async {
                self.posts = sorted
                self.errorText = nil
            }
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener = Firestore.firestore()
            .collection("users").document(uid).collection("posts")
            .addSnapshotListener { snap, err in
                if let err = err {
                    DispatchQueue.main.async {
                        self.errorText = "Fehler beim Laden: \(err.localizedDescription)"
                    }
                    return
                }
                let docs = snap?.documents ?? []
                let items: [YourPost] = docs.compactMap { doc in
                    let d = doc.data()
                    let au = (d["uid"] as? String) ?? uid
                    return YourPost(
                        id: doc.documentID,
                        authorUid: au,
                        username: (d["username"] as? String) ?? "",
                        pfpBase64: d["pfpData"] as? String,
                        imageBase64: (d["imageData"] as? String) ?? (d["imagePreview"] as? String) ?? "",
                        caption: (d["caption"] as? String) ?? "",
                        address: (d["address"] as? String) ?? "",
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue()
                    )
                }
                let sorted = items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                DispatchQueue.main.async {
                    self.posts = sorted
                    self.errorText = nil
                }
            }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func deletePost(_ post: YourPost) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FirestoreManager.shared.deletePost(authorUid: uid, postId: post.id)
            await MainActor.run {
                postToDelete = nil
            }
        } catch {
            await MainActor.run {
                self.errorText = "Löschen fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }
}

private struct YourPostRow: View {
    let post: YourPost
    let rdf: RelativeDateTimeFormatter
    let onDeleteTap: (YourPost) -> Void
    @State private var liveUsername: String?
    @State private var livePfp: String?
    @State private var authorListener: ListenerRegistration?

    private var effectivePfp: String? {
        if let livePfp, !livePfp.isEmpty { return livePfp }
        return post.pfpBase64
    }

    private var effectiveUsername: String {
        let candidate = (liveUsername?.isEmpty == false ? liveUsername! : post.username)
        return candidate.isEmpty ? "Unbekannt" : candidate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        Text(rdf.localizedString(for: ts, relativeTo: Date()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    onDeleteTap(post)
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
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
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !post.address.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    Text(post.address)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .glassCardEffect(cornerRadius: 16)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .onAppear { attachAuthorListener() }
        .onDisappear { detachAuthorListener() }
        .onChange(of: post.authorUid) { _, _ in
            detachAuthorListener()
            attachAuthorListener()
        }
    }

    private func attachAuthorListener() {
        guard !post.authorUid.isEmpty, authorListener == nil else { return }
        let ref = Firestore.firestore().collection("users").document(post.authorUid)
        authorListener = ref.addSnapshotListener(includeMetadataChanges: true) { snap, _ in
            guard let data = snap?.data() else { return }
            let name = data["username"] as? String ?? data["user_name"] as? String
            let pfp  = data["pfpData"] as? String ?? data["pfp_data"] as? String
            DispatchQueue.main.async {
                self.liveUsername = name
                self.livePfp = pfp
            }
        }
        ref.getDocument(source: .server) { snap, _ in
            guard let data = snap?.data() else { return }
            let name = data["username"] as? String ?? data["user_name"] as? String
            let pfp  = data["pfpData"] as? String ?? data["pfp_data"] as? String
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
}

private extension View {
    @ViewBuilder
    func glassCardEffect(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
                .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.7))
        }
    }
}

fileprivate extension UIImage {
    static func fromBase64(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}

private func sampleBase64Image(width: Int, height: Int, start: UIColor, end: UIColor, text: String? = nil) -> String {
    let size = CGSize(width: width, height: height)
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { ctx in
        let colors = [start.cgColor, end.cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0,1])!
        ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        if let text, !text.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(size.width, size.height)/6, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraph
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            let rect = CGRect(x: 0, y: size.height/2 - 24, width: size.width, height: 48)
            str.draw(in: rect)
        }
    }
    let data = img.jpegData(compressionQuality: 0.86) ?? Data()
    return data.base64EncodedString()
}

extension YourPostsView {
    static let samplePosts: [YourPost] = {
        let now = Date()
        let p1 = sampleBase64Image(width: 96, height: 96, start: .systemGreen, end: .systemTeal, text: "O")
        let p2 = sampleBase64Image(width: 96, height: 96, start: .systemOrange, end: .systemPink, text: "M")
        let p3 = sampleBase64Image(width: 96, height: 96, start: .systemBlue, end: .systemPurple, text: "L")
        let i1 = sampleBase64Image(width: 900, height: 600, start: .systemPink, end: .systemIndigo)
        let i2 = sampleBase64Image(width: 900, height: 900, start: .systemTeal, end: .systemYellow)
        let i3 = sampleBase64Image(width: 1200, height: 800, start: .systemPurple, end: .systemMint)
        return [
            YourPost(
                id: "mock-1",
                authorUid: "preview-olivia",
                username: "Olivia",
                pfpBase64: p1,
                imageBase64: i1,
                caption: "Sonnenuntergang am Kanal",
                address: "Berlin, Kreuzberg",
                createdAt: now.addingTimeInterval(-3600)
            ),
            YourPost(
                id: "mock-2",
                authorUid: "preview-max",
                username: "Max",
                pfpBase64: p2,
                imageBase64: i2,
                caption: "Erster Grow abgeschlossen",
                address: "Hamburg, Sternschanze",
                createdAt: now.addingTimeInterval(-86400)
            ),
            YourPost(
                id: "mock-3",
                authorUid: "preview-lena",
                username: "Lena",
                pfpBase64: p3,
                imageBase64: i3,
                caption: "Neue Sorte ausprobiert",
                address: "München",
                createdAt: now.addingTimeInterval(-172800)
            )
        ]
    }()
}

#Preview {
    YourPostsView()
}
