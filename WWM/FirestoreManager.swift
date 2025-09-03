//
//  FirestoreManager.swift
//  WWM
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct AppUser {
    let uid: String
    let email: String
    let username: String
    let pfpData: String?
}

final class FirestoreManager {
    static let shared = FirestoreManager()
    private init() {}

    private let db = Firestore.firestore()
    private var users: CollectionReference { db.collection("users") }

    func addUser(uid: String, email: String?, username: String, pfpData: String?) async throws {
        let data: [String: Any] = [
            "uid": uid,
            "email": email ?? "",
            "username": username,
            "pfpData": pfpData ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await users.document(uid).setData(data, merge: true)
    }

    func fetchCurrentUserProfile() async throws -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await users.document(uid).getDocument()
        return snap.get("pfpData") as? String
    }

    func updateProfileImageBase64(_ base64: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await users.document(uid).setData([
            "pfpData": base64,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func fetchCurrentUser() async throws -> AppUser? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await users.document(uid).getDocument()
        guard let data = snap.data() else { return nil }
        return AppUser(
            uid: data["uid"] as? String ?? "",
            email: data["email"] as? String ?? "",
            username: data["username"] as? String ?? "",
            pfpData: data["pfpData"] as? String
        )
    }
}


extension FirestoreManager {
    private var posts: CollectionReference { db.collection("posts") }

    func createPost(imageBase64: String,
                    caption: String?,
                    address: String?,
                    lat: Double?,
                    lng: Double?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let user = try? await fetchCurrentUser()

        var data: [String: Any] = [
            "uid": uid,
            "username": user?.username ?? "",
            "pfpData": user?.pfpData ?? "",
            "imageData": imageBase64,
            "caption": caption ?? "",
            "address": address ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ]

        if let lat = lat, let lng = lng {
            data["lat"] = lat
            data["lng"] = lng
        }

        try await posts.addDocument(data: data)
    }

    private func friends(of uid: String) -> CollectionReference {
        users.document(uid).collection("friends")
    }

    func fetchUser(byUsername username: String) async throws -> AppUser? {
        let snap = try await users
            .whereField("username", isEqualTo: username)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snap.documents.first else { return nil }
        let data = doc.data()
        return AppUser(
            uid: data["uid"] as? String ?? doc.documentID,
            email: data["email"] as? String ?? "",
            username: data["username"] as? String ?? "",
            pfpData: data["pfpData"] as? String
        )
    }

    func addFriend(between myUid: String, and otherUid: String) async throws {
        guard myUid != otherUid else { return }
        let batch = db.batch()
        let now = FieldValue.serverTimestamp()

        let aRef = friends(of: myUid).document(otherUid)
        let bRef = friends(of: otherUid).document(myUid)

        batch.setData(["since": now], forDocument: aRef, merge: true)
        batch.setData(["since": now], forDocument: bRef, merge: true)

        try await batch.commit()
    }

    func listenFriends(of uid: String, onChange: @escaping ([String]) -> Void) -> ListenerRegistration {
        friends(of: uid)
            .order(by: "since", descending: false)
            .addSnapshotListener { snapshot, _ in
                let ids = snapshot?.documents.map { $0.documentID } ?? []
                onChange(ids)
            }
    }

    func fetchUsers(byUIDs uids: [String]) async throws -> [AppUser] {
        guard !uids.isEmpty else { return [] }
        var result: [AppUser] = []

        let chunks = stride(from: 0, to: uids.count, by: 10)
            .map { Array(uids[$0..<min($0 + 10, uids.count)]) }

        for chunk in chunks {
            let snap = try await users
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for doc in snap.documents {
                let data = doc.data()
                result.append(AppUser(
                    uid: data["uid"] as? String ?? doc.documentID,
                    email: data["email"] as? String ?? "",
                    username: data["username"] as? String ?? "",
                    pfpData: data["pfpData"] as? String
                ))
            }
        }

        let order = Dictionary(uniqueKeysWithValues: uids.enumerated().map { ($1, $0) })
        return result.sorted { (order[$0.uid] ?? 0) < (order[$1.uid] ?? 0) }
    }
    
    func removeFriend(between myUid: String, and otherUid: String) async throws {
        guard myUid != otherUid else { return }
        let batch = db.batch()
        let aRef = friends(of: myUid).document(otherUid)
        let bRef = friends(of: otherUid).document(myUid)
        batch.deleteDocument(aRef)
        batch.deleteDocument(bRef)
        try await batch.commit()
    }
}
