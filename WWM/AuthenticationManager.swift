//
//  AuthenticationManager.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import Foundation
import FirebaseAuth

struct UserModel {
    
    var uid: String
    var email: String?
    
    init(_ user: User) {
        self.uid = user.uid
        self.email = user.email
    }
    
}

class AuthenticationManager {
    
    static let shared = AuthenticationManager()
    private init() {}
    
    func createUser(email: String, password: String) async throws -> UserModel {
        let user = try await Auth.auth().createUser(withEmail: email, password: password).user
        return UserModel(user)
    }
    
    func signInUser(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }
    
}
