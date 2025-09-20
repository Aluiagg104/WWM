//
//  ChatView.swift
//  WWM
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatView: View {
    let user: AppUser

    @State private var myUid: String = Auth.auth().currentUser?.uid ?? ""
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var listener: ListenerRegistration?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { m in
                            MessageRow(message: m, isMe: m.senderId == myUid)
                                .id(m.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Nachricht…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill").font(.title3)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
        .navigationTitle(user.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        myUid = Auth.auth().currentUser?.uid ?? ""
        stop()
        Task {
            // WICHTIG: Chat-Dokument (mit participants) sicherstellen, sonst blocken die Rules
            try? await FirestoreManager.shared.ensureChat(with: user.uid)

            // Badge-Logik: „Chats gesehen“ markieren
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "chats_last_seen_at")

            listener = FirestoreManager.shared.listenMessages(with: user.uid) { msgs in
                Task { @MainActor in
                    messages = msgs
                }
            }
        }
    }

    private func stop() {
        listener?.remove()
        listener = nil
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        do {
            try await FirestoreManager.shared.sendMessage(to: user.uid, text: text)
        } catch {
            print("send failed:", error.localizedDescription)
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let isMe: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            if isMe {
                Spacer(minLength: 40)
                bubble(text: message.text,
                       bg: Color(.systemGreen),
                       fg: .white,
                       align: .trailing)
            } else {
                bubble(text: message.text,
                       bg: Color(UIColor.secondarySystemBackground),
                       fg: .primary,
                       align: .leading)
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private func bubble(text: String, bg: Color, fg: Color, align: Alignment) -> some View {
        Text(text)
            .foregroundColor(fg)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity, alignment: align)
    }
}


extension FirestoreManager {
    func ensureChat(with otherUid: String) async throws {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let cid = chatId(between: myUid, and: otherUid)
        try await db.collection("chats").document(cid).setData([
            "participants": [myUid, otherUid],
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}
