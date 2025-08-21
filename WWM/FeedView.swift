//
//  FeedView.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import FirebaseAuth
import SwiftUI

struct Post: Identifiable {
    let id: String
    let place: String
    let authorName: String
    let authorPfpBase64: String?
    let strain: String
}

struct FeedView: View {
    @State private var showAuthSheet = true
    @StateObject private var userVM = CurrentUserViewModel()

    // Beispiel-Daten – später durch Firestore-Ladecode ersetzen
    @State private var posts: [Post] = [
        .init(id: UUID().uuidString, place: "Berlin", authorName: "Oliver",
              authorPfpBase64: UserDefaults.standard.string(forKey: "pfpBase64"),
              strain: "Indica")
    ]

    var body: some View {
        ZStack {
            Color(hex: "#EAEAEA").ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(posts) { post in
                        PostCardView(
                            place: post.place,
                            authorName: post.authorName,
                            authorPfpBase64: post.authorPfpBase64,
                            strain: post.strain
                        )
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: ProfileView(showAuthSheet: $showAuthSheet)) {
                    Base64ImageView(
                        base64: userVM.pfpBase64 ?? UserDefaults.standard.string(forKey: "pfpBase64"),
                        size: 28,
                        cornerRadius: 14
                    )
                }
            }
            ToolbarItem {
                NavigationLink(destination: Text("Post View")) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color(hex: "#EF476F"))
                }
            }
        }
        .toolbarBackground(Color(hex: "#55A630"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            showAuthSheet = Auth.auth().currentUser == nil
        }
        .task {
            await userVM.loadProfile()
            // TODO: hier später Posts aus Firestore laden und `posts` setzen
        }
        .fullScreenCover(isPresented: $showAuthSheet) {
            NavigationStack { AuthenticationView(showAuthSheet: $showAuthSheet) }
        }
    }
}

