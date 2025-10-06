import SwiftUI
import _PhotosUI_SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

extension View {
    @ViewBuilder
    func lgRect(_ radius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 0.6))
        }
    }

    @ViewBuilder
    func lgCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.6))
        }
    }

    @ViewBuilder
    func lgButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var pfpBase64: String? = nil
    @State private var isBusy = false
    @State private var errorText: String? = nil

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
            .padding()
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await loadPfp(from: newItem) }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.13, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Circle().fill(Color(red: 0.33, green: 0.77, blue: 0.39).opacity(0.28)).frame(width: 460, height: 460).blur(radius: 90).offset(x: -160, y: -260).allowsHitTesting(false)
            Circle().fill(Color(red: 0.96, green: 0.28, blue: 0.43).opacity(0.22)).frame(width: 380, height: 380).blur(radius: 100).offset(x: 180, y: -120).allowsHitTesting(false)
            Circle().fill(Color.blue.opacity(0.20)).frame(width: 520, height: 520).blur(radius: 140).offset(x: 80, y: 320).allowsHitTesting(false)
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            Text("Konto erstellen")
                .font(.largeTitle.weight(.semibold))

            VStack(spacing: 16) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let p = pfpBase64, let data = Data(base64Encoded: p), let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 128, height: 128)
                                .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 128, height: 128)
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: "camera")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(.black.opacity(0.6)))
                            .offset(x: 6, y: 6)
                    }
                }
                .buttonStyle(.plain)

                TextField("E-Mail", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .padding(14)
                    .lgRect(12)

                SecureField("Passwort", text: $password)
                    .padding(14)
                    .lgRect(12)

                TextField("Benutzername", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(14)
                    .lgRect(12)
            }

            if let e = errorText {
                Text(e)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .lgCapsule()
            }

            Button {
                Task { await createAccount() }
            } label: {
                Text("Erstellen")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .lgButtonStyle()
            
            Spacer()
        }
        .frame(maxWidth: 400)
    }

    private func loadPfp(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                if let img = UIImage(data: data) {
                    let jpeg = img.jpegData(compressionQuality: 0.85) ?? data
                    pfpBase64 = jpeg.base64EncodedString()
                } else {
                    pfpBase64 = data.base64EncodedString()
                }
            }
        } catch {
            pfpBase64 = nil
        }
    }

    private func createAccount() async {
        if isBusy { return }
        await MainActor.run { isBusy = true; errorText = nil }
        let rawName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let available = try await FirestoreManager.shared.isUsernameAvailable(rawName)
            if available == false {
                await MainActor.run {
                    errorText = "Benutzername ist bereits vergeben."
                    isBusy = false
                }
                return
            }
        } catch {
        }
        do {
            let user = try await AuthenticationManager.shared.createUser(email: email, password: password)
            do {
                try await FirestoreManager.shared.createUserProfileReservingUsername(uid: user.uid, email: user.email, username: rawName, pfpBase64: pfpBase64)
                await MainActor.run {
                    isBusy = false
                    dismiss()
                }
            } catch {
                do { try await Auth.auth().currentUser?.delete() } catch { }
                await MainActor.run {
                    if let nserr = error as NSError?, nserr.domain == "username_taken" {
                        errorText = "Benutzername ist bereits vergeben."
                    } else {
                        errorText = "Profil konnte nicht erstellt werden. Versuche es erneut."
                    }
                    isBusy = false
                }
            }
        } catch {
            await MainActor.run {
                if let e = error as? LocalizedError, let d = e.errorDescription {
                    errorText = d
                } else {
                    errorText = "Registrierung fehlgeschlagen."
                }
                isBusy = false
            }
        }
    }
}

#Preview {
    CreateAccountView()
}
