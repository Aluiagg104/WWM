//
//  FriendsView.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import SwiftUI
import FirebaseAuth

struct FriendsView: View {
    @Binding var showAuthSheet: Bool
    @StateObject private var userVM = CurrentUserViewModel()

    @State private var showScanner = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("👋 Noch keine Freunde")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Button("Freunde hinzufügen") {
                    print("Add Friend tapped")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {

                Button {
                    showScanner = true
                } label: {
                    Label("QR scannen", systemImage: "camera")
                }
                .fullScreenCover(isPresented: $showScanner) {
                    ScannerScreen { code in
                        print("✅ Gescannter Code:", code)
                        // z.B. Task { await handleScanned(uid: code) }

                        // Hier das Cover schließen:
                        showScanner = false
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    QRCodeView(text: userVM.username ?? "Username")
                } label: {
                    Image(systemName: "qrcode")
                }
            }
        }
        .task { await userVM.loadProfile() }
        .navigationTitle("Deine Freunde")
    }
    
    func handleScanned(uid: String) async {
        print(uid)
    }
}

