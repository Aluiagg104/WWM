import SwiftUI
import FirebaseAuth
import UIKit

private let SIDE_MARGIN: CGFloat = 32

struct ProfileView: View {
    @StateObject private var userVM = CurrentUserViewModel()
    @State private var signOutError: String?

    // Navigation-Push-States (ersetzt fullScreenCover)
    @State private var pushFriends = false
    @State private var pushYourPosts = false

    var body: some View {
        ZStack {
            LiquidGlassBackgroundProfile()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    // Profil-Header – NavigationLink zu ProfileEditView
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        HStack(spacing: 14) {
                            Base64ImageView(
                                base64: userVM.pfpBase64 ?? UserDefaults.standard.string(forKey: "pfpBase64"),
                                size: 80, cornerRadius: 40
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                Text(userVM.username ?? "Username")
                                    .font(.title2.weight(.semibold))
                                if let email = Auth.auth().currentUser?.email {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCardEffect(cornerRadius: 22)
                        .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)

                    // Kacheln: jetzt als NavigationLink-Labels (echtes Push)
                    VStack(spacing: 12) {
                        // Freunde
                        NavigationLink(isActive: $pushFriends) {
                            // Ziel: FriendsView nutzt das Binding, um „Schließen“ zu handhaben
                            FriendsView(ShowFriendsView: $pushFriends)
                        } label: {
                            GlassRowTile(
                                icon: "person.2.fill",
                                title: "Freunde",
                                trailing: { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                            )
                        }
                        .buttonStyle(.plain)

                        // Deine Beiträge
                        NavigationLink(isActive: $pushYourPosts) {
                            YourPostsView(ShowYourPostsView: $pushYourPosts)
                        } label: {
                            GlassRowTile(
                                icon: "photo",
                                title: "Deine Beiträge",
                                trailing: { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                            )
                        }
                        .buttonStyle(.plain)

                        // Abmelden bleibt Button (kein Push)
                        GlassRowButton(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "Abmelden",
                            tint: .red,
                            trailing: { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        ) {
                            performSignOut()
                        }
                    }

                    if let err = signOutError {
                        Text(err).font(.footnote).foregroundColor(.red)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .modifier(ScrollContentMargins(top: 0, horizontal: SIDE_MARGIN, bottom: 12))
        }
        .task { await userVM.loadProfile() }
        // Hinweis: keine fullScreenCover mehr – Navigation läuft über NavigationLink
    }

    // alter Material-Style (nur noch intern als Fallback genutzt)
    private var glassCardBackground: some ShapeStyle {
        .ultraThinMaterial
            .shadow(.inner(color: .white.opacity(0.08), radius: 1, x: 0, y: 1))
    }

    @MainActor
    private func performSignOut() {
        // Beim Logout keine offenen Push-Ziele
        pushFriends = false
        pushYourPosts = false
        do {
            try AuthenticationManager.shared.signOut()
            userVM.reset()
            UserDefaults.standard.removeObject(forKey: "pfpBase64")
        } catch {
            signOutError = error.localizedDescription
        }
    }
}

// MARK: - Kachel-Views

/// Label für NavigationLink mit Liquid-Glass-Look (kein Button!)
private struct GlassRowTile<Trailing: View>: View {
    let icon: String
    let title: String
    var tint: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(tint ?? .primary)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint ?? .primary)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardEffect(cornerRadius: 20) // echter Glass-Effekt + Fallback
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Button-Variante (für „Abmelden“)
private struct GlassRowButton<Trailing: View>: View {
    let icon: String
    let title: String
    var tint: Color? = nil
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassRowTile(icon: icon, title: title, tint: tint, trailing: trailing)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Layout & Background

private struct ScrollContentMargins: ViewModifier {
    let top: CGFloat
    let horizontal: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .contentMargins(.top, top, for: .scrollContent)
                .contentMargins(.horizontal, horizontal, for: .scrollContent)
                .contentMargins(.bottom, bottom, for: .scrollContent)
        } else {
            content
                .padding(.top, top)
                .padding(.horizontal, horizontal)
                .padding(.bottom, bottom)
        }
    }
}

private struct LiquidGlassBackgroundProfile: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                ? [Color.black, Color("#112318")]
                : [Color("#F2FFF7"), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            blob(color: Color("#55A630").opacity(0.28), size: 420, x: -120, y: -180, blur: 80)
            blob(color: Color("#EF476F").opacity(0.20), size: 380, x: 160, y: -140, blur: 100)
            blob(color: Color.blue.opacity(0.16), size: 460, x: 80, y: 300, blur: 120)
        }
    }
    private func blob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat, blur: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(x: x, y: y)
    }
}

// MARK: - Glass Helper (echtes Liquid Glass + Fallback)

private extension View {
    /// Umhüllt den Inhalt mit Liquid-Glass (iOS 26+) und bietet darunter ein Material-Fallback.
    @ViewBuilder
    func glassCardEffect(cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                self
                    .glassEffect(.regular.interactive(),
                                 in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
                .background(
                    .ultraThinMaterial.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 0.7)
                )
        }
    }
}
