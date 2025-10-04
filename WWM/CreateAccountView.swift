//
//  CreateAccountView.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import SwiftUI
import _PhotosUI_SwiftUI

struct CreateAccountView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var username: String = ""

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil

    // nur Logik: vermeiden, dass mehrfach geklickt wird
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "#EAEAEA")
                .ignoresSafeArea()

            VStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .clipShape(Circle())
                            .frame(maxWidth: 250, maxHeight: 250)
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(Color(hex: "#1A1A1A"))
                            .frame(maxWidth: 250, maxHeight: 250)
                    }
                }
                .onChange(of: selectedItem) { oldValue, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                        }
                    }
                }
                .padding()

                TextField("Email", text: $email)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                TextField("Username", text: $username)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Button {
                    guard !isWorking else { return }
                    isWorking = true

                    let imageToUse: UIImage = selectedImage ?? UIImage.defaultAvatar()
                    guard let pfpData = imageToBase64JPEG(imageToUse, quality: 0.7, maxDimension: 512) else {
                        isWorking = false
                        return
                    }

                    // Logik: Username UND pfp lokal behalten
                    UserDefaults.standard.set(pfpData, forKey: "pfpBase64")
                    UserDefaults.standard.set(username, forKey: "username")

                    Task {
                        do {
                            let user = try await AuthenticationManager.shared.createUser(email: email, password: password)
                            try await FirestoreManager.shared.addUser(
                                uid: user.uid,
                                email: user.email,
                                username: username,
                                pfpData: pfpData
                            )
                            isWorking = false
                            // Logik: nach Erfolg schließen (Root wechselt idR. über Auth-State)
                            dismiss()
                        } catch {
                            isWorking = false
                            print(error.localizedDescription)
                        }
                    }
                } label: {
                    Text("Create Account")
                        .foregroundStyle(Color(hex: "#2B2B2B"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color(hex: "#FFD166"))
                        .cornerRadius(8)
                }
            }
            .padding()
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "#55A630"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

fileprivate extension UIImage {
    static func defaultAvatar(
        side: CGFloat = 512,
        symbolName: String = "person.crop.circle.fill",
        bgColor: UIColor = .systemGray5,
        tintColor: UIColor = .systemGray
    ) -> UIImage {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let inset: CGFloat = side * 0.1
            let symbolRect = CGRect(x: inset, y: inset, width: side - inset*2, height: side - inset*2)

            let config = UIImage.SymbolConfiguration(pointSize: side * 0.7, weight: .regular)
            if let symbol = UIImage(systemName: symbolName, withConfiguration: config)?
                .withTintColor(tintColor, renderingMode: .alwaysOriginal) {
                symbol.draw(in: symbolRect)
            }
        }
    }
}
