//
//  FirestoreManager.swift
//  WWM
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct AppUser {
    let uid: String
    let email: String
    let username: String
    let pfpData: String?
}

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let text: String
    let senderId: String
    let createdAt: Date?
}

enum FirestorePostError: Error {
    case notAuthenticated
}

// MARK: - Manager

final class FirestoreManager {
    static let shared = FirestoreManager()
    private init() {}

    fileprivate let db = Firestore.firestore()
    fileprivate var users: CollectionReference { db.collection("users") }
}

// MARK: - Users

extension FirestoreManager {
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

    // ✅ NEU: Serverseitig "zuletzt Chats gesehen" setzen
    func markAllChatsSeen() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await users.document(uid).setData([
                "chatsLastSeenAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("markAllChatsSeen failed:", error.localizedDescription)
        }
    }

    // (optional) lesen, falls benötigt
    func fetchChatsLastSeenAt() async throws -> Date? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await users.document(uid).getDocument()
        return (snap.get("chatsLastSeenAt") as? Timestamp)?.dateValue()
    }
}

// MARK: - Posts

extension FirestoreManager {
    private var posts: CollectionReference { db.collection("posts") }

    func createPost(imageBase64: String,
                    caption: String?,
                    address: String?,
                    lat: Double?,
                    lng: Double?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw FirestorePostError.notAuthenticated }

        let user = try? await fetchCurrentUser()
        let username = user?.username ?? ""
        let pfp = user?.pfpData ?? ""

        var data: [String: Any] = [
            "uid": uid,
            "username": username,
            "pfpData": pfp,
            "imageData": imageBase64,
            "caption": caption ?? "",
            "address": address ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let lat, let lng {
            data["lat"] = lat
            data["lng"] = lng
        }
        try await posts.addDocument(data: data)
    }
}

// MARK: - Chats

extension FirestoreManager {
    private var chats: CollectionReference { db.collection("chats") }

    func chatId(between a: String, and b: String) -> String {
        a < b ? "\(a)_\(b)" : "\(b)_\(a)"
    }

    func listenMessages(with otherUid: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        guard let myUid = Auth.auth().currentUser?.uid else {
            return db.collection("_noop").addSnapshotListener { _, _ in }
        }
        let cid = chatId(between: myUid, and: otherUid)
        return chats.document(cid)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snap, _ in
                let items: [ChatMessage] = snap?.documents.compactMap { doc in
                    let d = doc.data()
                    return ChatMessage(
                        id: doc.documentID,
                        text: (d["text"] as? String) ?? "",
                        senderId: (d["senderId"] as? String) ?? "",
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue()
                    )
                } ?? []
                onChange(items)
            }
    }

    func sendMessage(to otherUid: String, text: String) async throws {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let cid = chatId(between: myUid, and: otherUid)
        let chatRef = chats.document(cid)

        try await chatRef.setData([
            "participants": [myUid, otherUid],
            "updatedAt": FieldValue.serverTimestamp(),
            "lastMessage": text,
            "lastSender": myUid
        ], merge: true)

        try await chatRef.collection("messages").document().setData([
            "text": text,
            "senderId": myUid,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func ensureChat(with otherUid: String) async throws {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let cid = chatId(between: myUid, and: otherUid)
        try await chats.document(cid).setData([
            "participants": [myUid, otherUid],
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}

// MARK: - Friends

extension FirestoreManager {
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
        let chunks = stride(from: 0, to: uids.count, by: 10).map { Array(uids[$0..<min($0 + 10, uids.count)]) }
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
        batch.deleteDocument(friends(of: myUid).document(otherUid))
        batch.deleteDocument(friends(of: otherUid).document(myUid))
        try await batch.commit()
    }
}

// MARK: - Username Index (transaction wrapped to async/await)

extension FirestoreManager {
    private var usernames: CollectionReference { db.collection("usernames") }

    func updateProfile(newUsername: String?, newPfpBase64: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw FirestorePostError.notAuthenticated }
        let userRef = users.document(uid)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            db.runTransaction({ [self] (txn, errorPointer) -> Any? in
                let userSnap: DocumentSnapshot
                do {
                    userSnap = try txn.getDocument(userRef)
                } catch let e as NSError {
                    errorPointer?.pointee = e
                    return nil
                }

                let currentData = userSnap.data() ?? [:]
                let oldUsername = (currentData["username"] as? String) ?? ""
                var updates: [String: Any] = [:]

                if let base64 = newPfpBase64 {
                    updates["pfpData"] = base64
                    updates["updatedAt"] = FieldValue.serverTimestamp()
                }

                if let newNameRaw = newUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !newNameRaw.isEmpty,
                   newNameRaw != oldUsername {

                    let oldKey = oldUsername.lowercased()
                    let newKey = newNameRaw.lowercased()

                    let newRef = self.usernames.document(newKey)

                    let newSnap: DocumentSnapshot
                    do {
                        newSnap = try txn.getDocument(newRef)
                    } catch let e as NSError {
                        errorPointer?.pointee = e
                        return nil
                    }

                    if newSnap.exists {
                        let owner = (newSnap.data()?["uid"] as? String) ?? ""
                        if owner != uid {
                            errorPointer?.pointee = NSError(domain: "username_taken", code: 1, userInfo: nil)
                            return nil
                        }
                    }

                    if !oldUsername.isEmpty, oldKey != newKey {
                        txn.deleteDocument(self.usernames.document(oldKey))
                    }

                    txn.setData(["uid": uid], forDocument: newRef, merge: false)
                    updates["username"] = newNameRaw
                }

                if !updates.isEmpty {
                    txn.setData(updates, forDocument: userRef, merge: true)
                }

                return nil
            }, completion: { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            })
        }
    }
}

// MARK: - Chats Seen (Server-Zeitstempel)
extension FirestoreManager {
    /// Setzt users/{uid}.chatsLastSeenAt auf serverTimestamp und aktualisiert auch den lokalen Cache.
    func markChatsSeenNow() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await users.document(uid).setData([
                "chatsLastSeenAt": FieldValue.serverTimestamp()
            ], merge: true)

            // lokaler Fallback, falls mal offline
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "chats_last_seen_at")
        } catch {
            print("markChatsSeenNow failed:", error.localizedDescription)
        }
    }
}
