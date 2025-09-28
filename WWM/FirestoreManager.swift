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
    // ⬇️ HIER zentral definieren (damit keine Dopplungen in Extensions entstehen)
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

// MARK: - Posts Helpers (nur einmal definiert)

fileprivate extension FirestoreManager {
    /// winziges Thumb (für Feed-Avatar im Post), ~10–30 KiB
    func tinyThumbBase64(from base64: String) -> String? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        // kleine Kante + moderate Qualität
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

    /// kleines Vorschau-Bild fürs Feed (damit das Hauptbild nicht inline sein muss)
    func previewBase64(from fullBase64: String) -> String? {
        guard let data = Data(base64Encoded: fullBase64, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        return img.base64UnderFirestoreLimit(
            maxBase64Bytes: 120 * 1024,   // ~120 KiB
            startMaxDim: 480,
            minMaxDim: 240,
            dimStep: 0.85,
            qualityStart: 0.9,
            qualityMin: 0.35,
            qualityStep: 0.1
        )
    }

    /// String in Blöcke aufteilen (Zeichen-basiert)
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

// MARK: - Posts (mit Firestore-Chunking & 'strain')

extension FirestoreManager {
    /// Abwärtskompatibel: alter Einstieg bleibt bestehen, ruft intern die chunking-Variante.
    func createPost(imageBase64: String,
                    caption: String?,
                    address: String?,
                    lat: Double?,
                    lng: Double?,
                    strain: String? = nil) async throws {
        try await createPostChunkedIfNeeded(imageBase64: imageBase64,
                                            caption: caption,
                                            address: address,
                                            lat: lat,
                                            lng: lng,
                                            strain: strain)
    }

    /// Speichert Post. Falls das Bild zu groß ist, wird es in Subcollection `/posts/{id}/chunks` gespeichert.
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

        // Vorschau fürs Feed
        let previewB64 = previewBase64(from: imageBase64)

        // konservativer Schwellwert, damit das Post-Dokument unter 1 MiB bleibt
        let inlineThreshold = 700 * 1024 // 700 KiB
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
        if let s = strain, !s.isEmpty { meta["strain"] = s }   // Sorte speichern

        if isInlineOK {
            meta["imageData"] = imageBase64
            try await postRef.setData(meta)
            return
        }

        // 1) Metadokument anlegen (ohne volles Bild)
        try await postRef.setData(meta)

        // 2) Bild in Chunks ablegen (je ~240k Zeichen)
        let parts = chunkBase64(imageBase64, maxChunkChars: 240_000)
        let chunkCol = postRef.collection("chunks")

        var batch = db.batch()
        for (i, part) in parts.enumerated() {
            let cRef = chunkCol.document(String(i))
            batch.setData(["uid": uid, "idx": i, "data": part], forDocument: cRef)
            if i % 450 == 449 { // Batch-Sicherheit
                try await batch.commit()
                batch = db.batch()
            }
        }
        try await batch.commit()
        try await postRef.setData(["chunkCount": parts.count], merge: true)
    }

    /// Vollständiges Bild wieder zusammensetzen (für Detailansicht).
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

// MARK: - Chats "gesehen" markieren (Badge zurücksetzen)

extension FirestoreManager {
    /// Merkt sich, dass Chats jetzt gesehen wurden.
    /// - Parameter graceSeconds: kleiner Puffer damit Serverzeiten (updatedAt) nicht knapp hinter dem lokalen Timestamp liegen.
    func markChatsSeenNow(graceSeconds: TimeInterval = 2.0) async {
        // 1) Lokal für Badge-Logik (FeedView etc.)
        let ts = Date().addingTimeInterval(graceSeconds).timeIntervalSince1970
        UserDefaults.standard.set(ts, forKey: "chats_last_seen_at")

        // 2) Optional: auch in /users/{uid} schreiben (gegen Geräteeuhr-Differenzen)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await users.document(uid).setData([
                "chatSeenAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            // nicht kritisch – Badge funktioniert auch rein lokal
            print("markChatsSeenNow write failed:", error.localizedDescription)
        }
    }

    /// Praktischer Helfer, falls du das Datum irgendwo brauchst.
    func localChatsLastSeen() -> Date {
        let raw = UserDefaults.standard.object(forKey: "chats_last_seen_at") as? Double ?? 0
        return Date(timeIntervalSince1970: raw)
    }
}
