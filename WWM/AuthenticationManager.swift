import Foundation
import FirebaseAuth

struct UserModel {
    var uid: String
    var email: String?
    init(_ user: User) {
        uid = user.uid
        email = user.email
    }
}

enum AuthFlowError: Error, LocalizedError {
    case tooManyRequests(String)
    case invalidCredential(String)
    case userDisabled(String)
    case wrongPassword(String)
    case userNotFound(String)
    case network(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .tooManyRequests(let m): return m
        case .invalidCredential(let m): return m
        case .userDisabled(let m): return m
        case .wrongPassword(let m): return m
        case .userNotFound(let m): return m
        case .network(let m): return m
        case .unknown(let m): return m
        }
    }
}

final class AuthenticationManager {
    static let shared = AuthenticationManager()
    private init() {}

    // MARK: - Sign in
    func signInUser(email: String, password: String) async throws {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        do {
            _ = try await Auth.auth().signIn(withEmail: e, password: p)
        } catch {
            throw mapAuthError(error)
        }
    }

    // MARK: - Create user
    func createUser(email: String, password: String) async throws -> UserModel {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await Auth.auth().createUser(withEmail: e, password: password)
            return UserModel(result.user)
        } catch {
            throw mapAuthError(error, isSignup: true)
        }
    }

    // MARK: - Sign out
    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Token sanft auffrischen
    func ensureFreshSession() async throws {
        guard let user = Auth.auth().currentUser else { return }
        do {
            _ = try await user.getIDTokenResult(forcingRefresh: false)
        } catch {
            _ = try await user.getIDTokenResult(forcingRefresh: true)
        }
    }

    // MARK: - Fehlerabbildung (versionssicher)
    private func mapAuthError(_ error: Error, isSignup: Bool = false) -> Error {
        guard let nserr = error as NSError?, nserr.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nserr.code) else {
            return AuthFlowError.unknown("Unbekannter Fehler.")
        }

        switch code {
        case .tooManyRequests:
            return AuthFlowError.tooManyRequests("Zu viele Versuche. Bitte kurz warten und ggf. VPN/Proxy deaktivieren.")
        case .invalidEmail, .invalidCredential:
            return AuthFlowError.invalidCredential("E-Mail ungültig.")
        case .wrongPassword:
            return AuthFlowError.wrongPassword("Passwort falsch.")
        case .userNotFound:
            return AuthFlowError.userNotFound("Kein Konto zu dieser E-Mail gefunden.")
        case .userDisabled:
            return AuthFlowError.userDisabled("Dieses Konto wurde deaktiviert.")
        case .networkError:
            return AuthFlowError.network("Keine Verbindung. Prüfe Internet/VPN.")
        case .emailAlreadyInUse where isSignup:
            return AuthFlowError.invalidCredential("Diese E-Mail ist bereits vergeben.")
        case .weakPassword where isSignup:
            return AuthFlowError.invalidCredential("Passwort zu schwach (mind. 6 Zeichen).")
        default:
            return AuthFlowError.unknown("Unbekannter Fehler (\(code.rawValue)).")
        }
    }
}
