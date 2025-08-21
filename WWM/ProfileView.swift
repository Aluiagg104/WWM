//
//  ProfileView.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import SwiftUI
import FirebaseAuth
import UIKit

struct ProfileView: View {
    @Binding var showAuthSheet: Bool
    @StateObject private var userVM = CurrentUserViewModel()
    
    @State private var ShowFriendsView: Bool = false

    var body: some View {
        ZStack {
            Color("#EAEAEA").ignoresSafeArea()
            
            ScrollView {
                Section {
                    Button(action: {
                        print("button clicked 7")
                    }) {
                        HStack {
                            Base64ImageView(
                                base64: userVM.pfpBase64 ?? UserDefaults.standard.string(forKey: "pfpBase64"),
                                size: 120,
                                cornerRadius: 60
                            )
                            Spacer()
                            Text(userVM.username ?? "Username")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(">")
                        }
                        .padding()
                        .foregroundColor(.white)
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding()
                }
                
                Section {
                    Button(action: {
                        ShowFriendsView = true
                    }) {
                        HStack {
                            Image(systemName: "person.2.fill")
                            
                            Text("Freunde")
                            
                            Spacer()
                            
                            Text(">")
                        }
                        .padding()
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding()
                }
                // z. B. in ProfileView
                .fullScreenCover(isPresented: $ShowFriendsView) {
                    NavigationStack {
                        FriendsView(showAuthSheet: $showAuthSheet)
                    }
                }

            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Einstellungen")
        .toolbarBackground(Color(hex: "#55A630"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await userVM.loadProfile() }
        
        Spacer()
        
    }
}
