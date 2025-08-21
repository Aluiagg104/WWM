//
//  AuthenticationView.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import SwiftUI

struct AuthenticationView: View {
    @Binding var showAuthSheet: Bool
    
    var body: some View {
        ZStack {
            Color(hex: "#1B4332")
                .ignoresSafeArea()
            
            VStack {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                
                NavigationLink(destination: SignInView(showAuthSheet: $showAuthSheet)) {
                    Text("Sign In")
                        .foregroundStyle(Color(hex: "#F8F9FA"))
                        .font(.title)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color(hex: "#EF476F"))
                        .cornerRadius(8)
                }
                
                NavigationLink(destination: CreateAccountView(showAuthSheet: $showAuthSheet)) {
                    Text("Create Account")
                        .foregroundStyle(Color(hex: "#F8F9FA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color(hex: "#2B2B2B"))
                        .cornerRadius(8)
                }
                
                Spacer()
                
                Text("18+ Community, Education, Experience")
                    .foregroundStyle(Color(hex: "#1A1A1A"))
            }
            .padding()
        }
    }
}

#Preview {
    NavigationStack {
        AuthenticationView(showAuthSheet: .constant(true))
    }
}
