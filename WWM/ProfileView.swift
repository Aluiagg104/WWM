import SwiftUI
import FirebaseAuth
import UIKit

private let SIDE_MARGIN: CGFloat = 32

struct ProfileView: View {
    @Binding var showAuthSheet: Bool
    @StateObject private var userVM = CurrentUserViewModel()

    @State private var signOutError: String?
    @State private var ShowFriendsView = false
    @State private var ShowYourPostsView = false

    var body: some View {
        ZStack {
            LiquidGlassBackgroundProfile()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    NavigationLink { ProfileEditView() } label: {
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
                        .padding(16) // nur Innenabstand der Karte
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(glassCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)

                    // Aktionen (kein äußeres .padding mehr)
                    VStack(spacing: 12) {
                        GlassRowButton(icon: "person.2.fill", title: "Freunde",
                                       trailing: { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }) {
                            ShowFriendsView = true
                        }
                        GlassRowButton(icon: "photo", title: "Deine Beiträge",
                                       trailing: { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }) {
                            ShowYourPostsView = true
                        }
                        GlassRowButton(icon: "rectangle.portrait.and.arrow.right", title: "Abmelden", tint: .red,
                                       trailing: { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }) {
                            do {
                                try AuthenticationManager.shared.signOut()
                                UserDefaults.standard.removeObject(forKey: "pfpBase64")
                                showAuthSheet = true
                            } catch { signOutError = error.localizedDescription }
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
        .fullScreenCover(isPresented: $ShowFriendsView) {
            NavigationStack { FriendsView(showAuthSheet: $showAuthSheet, ShowFriendsView: $ShowFriendsView) }
        }
        .fullScreenCover(isPresented: $ShowYourPostsView) {
            NavigationStack { YourPostsView(ShowYourPostsView: $ShowYourPostsView) }
        }
    }

    private var glassCardBackground: some ShapeStyle {
        .ultraThinMaterial
            .shadow(.inner(color: .white.opacity(0.08), radius: 1, x: 0, y: 1))
    }
}

// Glasige Row-Buttons: Innenabstände bleiben, erzeugen keine äußeren Ränder
private struct GlassRowButton<Trailing: View>: View {
    let icon: String
    let title: String
    var tint: Color? = nil
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct ScrollContentMargins: ViewModifier {
    let top: CGFloat
    let horizontal: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .contentMargins(.top, top, for: .scrollContent)           // weiter runter
                .contentMargins(.horizontal, horizontal, for: .scrollContent)
                .contentMargins(.bottom, bottom, for: .scrollContent)
        } else {
            // iOS 16 Fallback
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
                ? [Color.black, Color(hex: "#112318")]
                : [Color(hex: "#F2FFF7"), Color.white],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            blob(color: Color(hex: "#55A630").opacity(0.28), size: 420, x: -120, y: -180, blur: 80)
            blob(color: Color(hex: "#EF476F").opacity(0.20), size: 380, x: 160, y: -140, blur: 100)
            blob(color: Color.blue.opacity(0.16), size: 460, x: 80, y: 300, blur: 120)
        }
    }
    private func blob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat, blur: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size).blur(radius: blur).offset(x: x, y: y)
    }
}
