//
//  FriendsView.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import SwiftUI

struct FriendsView: View {
    @Binding var showAuthSheet: Bool
    @StateObject private var userVM = CurrentUserViewModel()

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
                    print("open QR Code Scanner")
                } label: {
                    Image(systemName: "camera")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    print("show qr code")
                } label: {
                    Image(systemName: "qrcode")
                }
            }
        }
        .task { await userVM.loadProfile() }
        .navigationTitle("Deine Freunde")
    }
}

