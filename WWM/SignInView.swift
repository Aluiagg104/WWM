//
//  SignInView.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import SwiftUI

struct SignInView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    
    @Binding var showAuthSheet: Bool
    
    var body: some View {
        ZStack {
            Color(hex: "#EAEAEA")
                .ignoresSafeArea()
            
            VStack {
                TextField("Email", text: $email)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                Spacer()
                
                Button {
                    Task {
                        do {
                            try await AuthenticationManager.shared.signInUser(email: email, password: password)
                            showAuthSheet = false
                        } catch {
                            print(error.localizedDescription)
                        }
                    }
                } label: {
                    Text("Sign In")
                        .foregroundStyle(Color(hex: "#2B2B2B"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color(hex: "#FFD166"))
                        .cornerRadius(8)
                }
                
            }
            .padding()
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "#55A630"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    NavigationStack {
        SignInView(showAuthSheet: .constant(true))
    }
}
