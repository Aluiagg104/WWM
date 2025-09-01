//
//  YourPostsView.swift
//  WWM
//
//  Created by Oliver Henkel on 01.09.25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct YourPost: Identifiable, Hashable {
    let id: String
    let username: String
    let pfpBase64: String?
    let imageBase64: String
    let caption: String
    let address: String
    let createdAt: Date?
}

struct YourPostsView: View {
    @Binding var ShowYourPostsView: Bool

    @State private var errorText: String?
    @State private var posts: [YourPost] = []
    @State private var listener: ListenerRegistration?

    @State private var postToDelete: YourPost?
    @State private var showDeleteAlert = false

    var body: some View {
        ZStack {
            ScrollView {
                if let err = errorText {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.horizontal)
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
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(posts) { post in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Base64ImageView(base64: post.pfpBase64, size: 36, cornerRadius: 18)
                                    Text(post.username.isEmpty ? "Unbekannt" : post.username)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer(minLength: 8)
                                    if let ts = post.createdAt {
                                        Text(RelativeDateTimeFormatter().localizedString(for: ts, relativeTo: Date()))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    Button {
                                        postToDelete = post
                                        showDeleteAlert = true
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
                                        .lineLimit(nil)
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
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 8, y: 4)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Deine Beiträge")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { ShowYourPostsView = false } label: { Image(systemName: "xmark") }
            }
        }
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
        .background(.background)
    }

    private func startListening() {
        stopListening()
        guard let uid = Auth.auth().currentUser?.uid else { return }

        listener = Firestore.firestore()
            .collection("posts")
            .whereField("uid", isEqualTo: uid)
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
                    return YourPost(
                        id: doc.documentID,
                        username: (d["username"] as? String) ?? "",
                        pfpBase64: d["pfpData"] as? String,
                        imageBase64: (d["imageData"] as? String) ?? "",
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
        do {
            try await Firestore.firestore()
                .collection("posts")
                .document(post.id)
                .delete()
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

fileprivate extension UIImage {
    static func fromBase64(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
