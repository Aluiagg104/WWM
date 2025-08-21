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
    
    @Binding var showAuthSheet: Bool
    
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
                        if let data = try? await newValue?.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) {
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
                    guard let image = selectedImage,
                          let pfpData = imageToBase64JPEG(image, quality: 0.7, maxDimension: 512) else {
                        return
                    }

                    // sofort lokal cachen, damit die UI direkt was hat
                    UserDefaults.standard.set(pfpData, forKey: "pfpBase64")

                    Task {
                        do {
                            let user = try await AuthenticationManager.shared.createUser(email: email, password: password)
                            // user ist vom Typ UserModel
                            try await FirestoreManager.shared.addUser(
                                uid: user.uid,
                                email: user.email,
                                username: username,
                                pfpData: pfpData
                            )
                            showAuthSheet = false
                        } catch {
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
