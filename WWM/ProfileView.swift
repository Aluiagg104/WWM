//
//  ProfileView.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @Binding var showAuthSheet: Bool
    
    var body: some View {
        ZStack {
            Color(hex: "#EAEAEA")
                .ignoresSafeArea()
            
            VStack {
                Button {
                    do {
                        try Auth.auth().signOut()
                        showAuthSheet = true
                    } catch {
                        print(error.localizedDescription)
                    }
                } label: {
                    Text("Sign Out")
                        .foregroundStyle(Color(hex: "#F8F9FA"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color(hex: "#2B2B2B"))
                        .cornerRadius(8)
                }
                .padding()
                
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView(showAuthSheet: .constant(false))
    }
}
