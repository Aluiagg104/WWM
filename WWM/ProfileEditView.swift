//
//  ProfileEditView.swift
//  WWM
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var originalUsername: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var originalBase64: String?
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var infoText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Avatar
                VStack(spacing: 12) {
                    ZStack {
                        if let img = pickedImage ?? base64ToImage(originalBase64) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color(UIColor.separator), lineWidth: 0.5))
                                .shadow(radius: 6)
                        } else {
                            Circle()
                                .fill(Color(UIColor.secondarySystemBackground))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 72))
                                        .foregroundColor(.secondary)
                                )
                                .overlay(Circle().stroke(Color(UIColor.separator), lineWidth: 0.5))
                        }

                        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.blue)
                                .clipShape(Circle())
                                .shadow(radius: 3)
                        }
                        .offset(x: 44, y: 44)
                        .onChange(of: selectedItem) { _, newItem in
                            Task { await loadPickedImage(newItem) }
                        }
                    }

                    if pickedImage != nil {
                        Button(role: .destructive) { pickedImage = nil } label: {
                            Label("Bild entfernen", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)

                // Username
                VStack(alignment: .leading, spacing: 8) {
                    Text("Benutzername").font(.headline)
                    TextField("Neuer Benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: username) { new, _ in
                            username = sanitizeUsername(new)
                        }

                    Text("Nur Buchstaben, Zahlen, Unterstrich; 3–20 Zeichen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let info = infoText {
                    Text(info).font(.footnote).foregroundStyle(.secondary)
                }
                if let err = errorText {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Speichern", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving)
            }
            .padding(16)
        }
        .navigationTitle("Profil bearbeiten")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
                    .disabled(isSaving)
            }
        }
        .task { await loadCurrent() }
    }

    // MARK: - State & Helpers

    private var hasChanges: Bool {
        let nameChanged = !username.isEmpty && username != originalUsername
        let imageChanged = pickedImage != nil
        return nameChanged || imageChanged
    }

    private func sanitizeUsername(_ s: String) -> String {
        // erlaubt a–z 0–9 und _ ; trim + limit 20
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = trimmed.lowercased().filter { c in
            c.isLetter || c.isNumber || c == "_"
        }
        return String(allowed.prefix(20))
    }

    private func base64ToImage(_ b64: String?) -> UIImage? {
        guard let b64, let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }

    private func loadCurrent() async {
        do {
            if let user = try await FirestoreManager.shared.fetchCurrentUser() {
                await MainActor.run {
                    username = user.username
                    originalUsername = user.username
                    originalBase64 = user.pfpData
                }
            }
        } catch {
            await MainActor.run { errorText = "Profil konnte nicht geladen werden: \(error.localizedDescription)" }
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                // leichte Downsizing-Strategie für Edit
                let downsized = img.downscaledToFit(maxPixel: 1024)
                await MainActor.run {
                    pickedImage = downsized
                    infoText = "Neues Bild ausgewählt."
                }
            }
        } catch {
            await MainActor.run { errorText = "Bild konnte nicht geladen werden." }
        }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        infoText = nil
        defer { isSaving = false }

        // Username validieren
        let newUsername = username
        guard newUsername.count >= 3 else {
            errorText = "Benutzername ist zu kurz."
            return
        }

        // Bild -> Base64 (unter ~950 KB)  ❗️verwende die Funktion aus UIImage+Resize.swift
        var newBase64: String? = nil
        if let img = pickedImage {
            guard let b64 = img.base64Under950KB() else {
                errorText = "Bild ist zu groß. Bitte ein kleineres Bild wählen."
                return
            }
            newBase64 = b64
        }

        do {
            try await FirestoreManager.shared.updateProfile(
                newUsername: newUsername,
                newPfpBase64: newBase64
            )
            await MainActor.run {
                infoText = "Profil gespeichert."
                originalUsername = newUsername
                if newBase64 != nil { originalBase64 = newBase64; pickedImage = nil }
                dismiss()
            }
        } catch let err as NSError {
            if err.domain == "username_taken" {
                errorText = "Benutzername ist bereits vergeben."
            } else {
                errorText = "Speichern fehlgeschlagen: \(err.localizedDescription)"
            }
        } catch {
            errorText = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
