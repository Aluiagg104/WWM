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
        ZStack {
            // 🔮 Glasiger Hintergrund über den ganzen Screen
            LiquidGlassBackgroundEdit()
                .ignoresSafeArea()

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
                            .onChange(of: selectedItem) { oldValue, newItem in
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

                        // 🔮 Liquid-Glass TextField
                        TextField("Neuer Benutzername", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.28), lineWidth: 0.7)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                            .onChange(of: username) { oldValue, new in
                                username = sanitizeUsername(new)
                            }

                        Text("Nur Buchstaben, Zahlen, Unterstrich; 3–20 Zeichen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

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
            .scrollIndicators(.hidden)
            .background(Color.clear) // ScrollView selbst bleibt transparent
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
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // A–Z, a–z, 0–9 und _
        let allowedSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

        let scalars = trimmed.unicodeScalars.filter { allowedSet.contains($0) }
        return String(String.UnicodeScalarView(scalars).prefix(20))
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

        let newUsername = username
        guard newUsername.count >= 3 else {
            errorText = "Benutzername ist zu kurz."
            return
        }

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

//
// MARK: - Liquid Glass Hintergrund für den Editor
//
private struct LiquidGlassBackgroundEdit: View {
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

            // sanfte „Blobs“
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
