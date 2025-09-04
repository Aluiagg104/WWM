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

    @State private var signOutError: String?
    @State private var ShowFriendsView: Bool = false
    @State private var ShowYourPostsView: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Button {
                    } label: {
                        HStack(spacing: 12) {
                            Base64ImageView(
                                base64: userVM.pfpBase64 ?? UserDefaults.standard.string(forKey: "pfpBase64"),
                                size: 80,
                                cornerRadius: 40
                            )
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(userVM.username ?? "Username")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let email = Auth.auth().currentUser?.email {
                                    Text(email).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(UIColor.separator), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            ShowFriendsView = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(.primary)
                                Text("Freunde")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)

                        Button {
                            ShowYourPostsView = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .foregroundStyle(.primary)
                                Text("Deine Beiträge")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    Button {
                        do {
                            try AuthenticationManager.shared.signOut()
                            UserDefaults.standard.removeObject(forKey: "pfpBase64")
                            showAuthSheet = true
                        } catch {
                            signOutError = error.localizedDescription
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Abmelden")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundColor(.red)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(UIColor.separator), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    if let err = signOutError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Einstellungen")
        .toolbarBackground(Color(hex: "#55A630"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await userVM.loadProfile() }
        .fullScreenCover(isPresented: $ShowFriendsView) {
            NavigationStack {
                FriendsView(showAuthSheet: $showAuthSheet, ShowFriendsView: $ShowFriendsView)
            }
        }
        .fullScreenCover(isPresented: $ShowYourPostsView) {
            NavigationStack {
                YourPostsView(ShowYourPostsView: $ShowYourPostsView)
            }
        }
    }
}
