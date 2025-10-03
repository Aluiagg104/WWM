//
//  StartView.swift
//  WWM
//
//  Created by Oliver Henkel on 29.09.25.
//

import SwiftUI

struct StartView: View {
    var body: some View {
        TabView {
            Tab("Feed", systemImage: "house.fill") {
                NavigationStack {
                    FeedView()
                        .navigationTitle("Feed")
                }
            }
            Tab("Post", systemImage: "plus.app.fill") {
                NavigationStack {
                    PostView()
                        .navigationTitle("Neuer Post")
                }
            }
            Tab("Profil", systemImage: "person.crop.circle.fill") {
                NavigationStack {
                    ProfileView()
                        .navigationTitle("Profil")
                }
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)     // echter Glas-Blur
        .toolbarBackgroundVisibility(.visible, for: .tabBar)     // Hintergrund sichtbar erzwingen
    }
}

extension View {
    func enrichTabBarGlass() -> some View {
        self
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            .overlay {
                // zarter Glare oben auf der Tabbar
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .top, endPoint: .center
                    )
                    .frame(height: 8)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .bottom)
                }
            }
    }
}
