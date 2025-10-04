//
//  FirestoreManager.swift
//  WWM
//

import Foundation
import UIKit
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
    fileprivate var posts: CollectionReference { db.collection("posts") }
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
}

// MARK: - Posts Helpers

fileprivate extension FirestoreManager {
    func tinyThumbBase64(from base64: String) -> String? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        return img.base64UnderFirestoreLimit(
            maxBase64Bytes: 30 * 1024,
            startMaxDim: 96,
            minMaxDim: 48,
            dimStep: 0.85,
            qualityStart: 0.9,
            qualityMin: 0.35,
            qualityStep: 0.1
        )
    }

    func previewBase64(from fullBase64: String) -> String? {
        guard let data = Data(base64Encoded: fullBase64, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        return img.base64UnderFirestoreLimit(
            maxBase64Bytes: 120 * 1024,
            startMaxDim: 480,
            minMaxDim: 240,
            dimStep: 0.85,
            qualityStart: 0.9,
            qualityMin: 0.35,
            qualityStep: 0.1
        )
    }

    func chunkBase64(_ s: String, maxChunkChars: Int) -> [String] {
        guard s.count > maxChunkChars else { return [s] }
        var res: [String] = []
        var start = s.startIndex
        while start < s.endIndex {
            let end = s.index(start, offsetBy: maxChunkChars, limitedBy: s.endIndex) ?? s.endIndex
            res.append(String(s[start..<end]))
            start = end
        }
        return res
    }
}

// MARK: - Posts

extension FirestoreManager {
    func createPost(imageBase64: String,
                    caption: String?,
                    address: String?,
                    lat: Double?,
                    lng: Double?,
                    strain: String? = nil) async throws {
        try await createPostChunkedIfNeeded(imageBase64: imageBase64,
                                            caption: caption,
                                            address: address,
                                            lat: lat, lng: lng,
                                            strain: strain)
    }

    func createPostChunkedIfNeeded(imageBase64: String,
                                   caption: String?,
                                   address: String?,
                                   lat: Double?,
                                   lng: Double?,
                                   strain: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw FirestorePostError.notAuthenticated }

        let me = try? await fetchCurrentUser()
        let username = me?.username ?? ""
        let pfpThumb = me?.pfpData.flatMap { tinyThumbBase64(from: $0) } ?? ""
        let previewB64 = previewBase64(from: imageBase64)

        let inlineThreshold = 700 * 1024
        let isInlineOK = imageBase64.lengthOfBytes(using: .utf8) <= inlineThreshold

        let postRef = posts.document()
        var meta: [String: Any] = [
            "uid": uid,
            "username": username,
            "pfpThumb": pfpThumb,
            "caption": caption ?? "",
            "address": address ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "hasChunks": !isInlineOK
        ]
        if let lat, let lng { meta["lat"] = lat; meta["lng"] = lng }
        if let previewB64 { meta["imagePreview"] = previewB64 }
        if let s = strain, !s.isEmpty { meta["strain"] = s }

        if isInlineOK {
            meta["imageData"] = imageBase64
            try await postRef.setData(meta)
            return
        }

        try await postRef.setData(meta)

        let parts = chunkBase64(imageBase64, maxChunkChars: 240_000)
        let chunkCol = postRef.collection("chunks")

        var batch = db.batch()
        for (i, part) in parts.enumerated() {
            let cRef = chunkCol.document(String(i))
            batch.setData(["uid": uid, "idx": i, "data": part], forDocument: cRef)
            if i % 450 == 449 {
                try await batch.commit()
                batch = db.batch()
            }
        }
        try await batch.commit()
        try await postRef.setData(["chunkCount": parts.count], merge: true)
    }

    func fetchPostImageBase64(postId: String) async throws -> String? {
        let postRef = posts.document(postId)
        let snap = try await postRef.getDocument()
        let d = snap.data() ?? [:]
        if let inline = d["imageData"] as? String { return inline }

        let q = postRef.collection("chunks").order(by: "idx", descending: false)
        let chunkSnap = try await q.getDocuments()
        let parts = chunkSnap.documents.compactMap { $0.data()["data"] as? String }
        guard !parts.isEmpty else { return nil }
        return parts.joined()
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

    /// ⚠️ WICHTIG: Gegenrichtung nur **anlegen**, wenn sie fehlt.
    /// Sonst wäre es ein "update" auf fremdem Pfad und scheitert an den Rules.
    func addFriend(between myUid: String, and otherUid: String) async throws {
        guard myUid != otherUid else { return }
        let now = FieldValue.serverTimestamp()

        let aRef = friends(of: myUid).document(otherUid)
        let bRef = friends(of: otherUid).document(myUid)

        // eigene Seite (update/create erlaubt)
        try await aRef.setData(["since": now], merge: true)

        // Gegenstück nur erstellen, falls es noch NICHT existiert
        let bSnap = try await bRef.getDocument()
        if !bSnap.exists {
            try await bRef.setData(["since": now]) // create (kein merge => wird als create bewertet)
        }
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

    /// Löscht beide Richtungen. Beide Deletes sind durch die Rules erlaubt.
    func removeFriend(between myUid: String, and otherUid: String) async throws {
        guard myUid != otherUid else { return }
        let aRef = friends(of: myUid).document(otherUid)
        let bRef = friends(of: otherUid).document(myUid)

        // erst eigene Seite hart löschen
        try await aRef.delete()

        // Gegenstück best-effort
        do { try await bRef.delete() }
        catch { print("reverse friend doc delete failed:", error.localizedDescription) }
    }
}

// MARK: - Username Index (Transaction)

extension FirestoreManager {
    private var usernames: CollectionReference { db.collection("usernames") }

    func updateProfile(newUsername: String?, newPfpBase64: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw FirestorePostError.notAuthenticated }
        let userRef = users.document(uid)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            db.runTransaction({ [self] (txn, errorPointer) -> Any? in
                let userSnap: DocumentSnapshot
                do { userSnap = try txn.getDocument(userRef) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }

                let currentData = userSnap.data() ?? [:]
                let oldUsername = (currentData["username"] as? String) ?? ""
                var updates: [String: Any] = [:]

                if let base64 = newPfpBase64 {
                    updates["pfpData"] = base64
                    updates["updatedAt"] = FieldValue.serverTimestamp()
                }

                if let newNameRaw = newUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !newNameRaw.isEmpty, newNameRaw != oldUsername {

                    let oldKey = oldUsername.lowercased()
                    let newKey = newNameRaw.lowercased()

                    let newRef = self.usernames.document(newKey)
                    let newSnap: DocumentSnapshot
                    do { newSnap = try txn.getDocument(newRef) }
                    catch let e as NSError { errorPointer?.pointee = e; return nil }

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
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: ()) }
            })
        }
    }
}

// MARK: - Chats "gesehen"

extension FirestoreManager {
    func markChatsSeenNow(graceSeconds: TimeInterval = 2.0) async {
        let ts = Date().addingTimeInterval(graceSeconds).timeIntervalSince1970
        UserDefaults.standard.set(ts, forKey: "chats_last_seen_at")

        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await users.document(uid).setData([
                "chatSeenAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("markChatsSeenNow write failed:", error.localizedDescription)
        }
    }

    func localChatsLastSeen() -> Date {
        let raw = UserDefaults.standard.object(forKey: "chats_last_seen_at") as? Double ?? 0
        return Date(timeIntervalSince1970: raw)
    }
}

// MARK: - Friend Codes (Kurz-IDs)

private let kFriendCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // ohne 0,O,1,I
private func randomFriendCode(length: Int = 10) -> String {
    String((0..<length).map { _ in kFriendCodeAlphabet.randomElement()! })
}

extension FirestoreManager {
    private var friendcodes: CollectionReference { db.collection("friendcodes") }

    /// Erzeugt einmalig einen Freundes-Code. User-Feld enthält **mit '#'**, Index-Dokument **ohne '#'**.
    @discardableResult
    func ensureFriendCodeExists() async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw FirestorePostError.notAuthenticated }
        let userRef = users.document(uid)

        if let snapshot = try? await userRef.getDocument(),
           let existing = snapshot.get("friendCode") as? String, !existing.isEmpty {
            return existing.hasPrefix("#") ? existing : "#"+existing
        }

        for _ in 0..<5 {
            let displayCode = "#"+randomFriendCode()
            let codeId = displayCode
                .uppercased()
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: " ", with: "")

            let created: String = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                db.runTransaction({ [self] txn, errPtr -> Any? in
                    let userSnap: DocumentSnapshot
                    do { userSnap = try txn.getDocument(userRef) }
                    catch let e as NSError { errPtr?.pointee = e; return nil }

                    if let already = userSnap.data()?["friendCode"] as? String, !already.isEmpty {
                        return already.hasPrefix("#") ? already : "#"+already
                    }

                    let codeRef = friendcodes.document(codeId) // ⬅️ Index OHNE '#'
                    let codeSnap: DocumentSnapshot
                    do { codeSnap = try txn.getDocument(codeRef) }
                    catch let e as NSError { errPtr?.pointee = e; return nil }

                    if codeSnap.exists {
                        errPtr?.pointee = NSError(domain: "friendcode_conflict", code: 1)
                        return nil
                    }

                    txn.setData(["uid": uid, "createdAt": FieldValue.serverTimestamp()], forDocument: codeRef, merge: false)
                    txn.setData(["friendCode": displayCode], forDocument: userRef, merge: true)
                    return displayCode
                }, completion: { result, err in
                    if let err { cont.resume(throwing: err) }
                    else if let code = result as? String { cont.resume(returning: code) }
                    else { cont.resume(throwing: NSError(domain: "unknown", code: -1)) }
                })
            }

            return created
        }

        throw NSError(domain: "friendcode_conflict", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Konnte keinen eindeutigen Code erzeugen."])
    }

    /// Holt Nutzer über Kurz-ID (# optional; case-insensitive).
    func fetchUser(byFriendCode raw: String) async throws -> AppUser? {
        let codeId = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard !codeId.isEmpty else { return nil }

        let codeSnap = try await friendcodes.document(codeId).getDocument()
        guard let uid = codeSnap.data()?["uid"] as? String else { return nil }

        let userSnap = try await users.document(uid).getDocument()
        guard let d = userSnap.data() else { return nil }
        return AppUser(
            uid: d["uid"] as? String ?? uid,
            email: d["email"] as? String ?? "",
            username: d["username"] as? String ?? "",
            pfpData: d["pfpData"] as? String
        )
    }

    func addFriend(byFriendCode raw: String) async throws {
        guard let myUid = Auth.auth().currentUser?.uid else { throw FirestorePostError.notAuthenticated }
        guard let user = try await fetchUser(byFriendCode: raw) else {
            throw NSError(domain: "friendcode_not_found", code: 404)
        }
        try await addFriend(between: myUid, and: user.uid)
    }
}
