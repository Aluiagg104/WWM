//
//  ChatView.swift
//  WWM
//
//  Created by Oliver Henkel on 04.09.25.
//

import SwiftUI
import UIKit

struct Message: Identifiable {
    var id: UUID = UUID()
    var text: String
}

struct Chat: View {
    @Binding var Messages: [Message]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Messages) { msg in
                    Text(msg.text)
                        .padding(10)
                        .background(Color(.systemGreen))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct ChatView: View {
    let user: AppUser
    @State private var Inputtext: String = ""
    
    //Temporer:
    @State private var Messages: [Message] = []
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            VStack {
                VStack {
                    Chat(Messages: $Messages)
                }
                .padding()
                
                Spacer()
                
                HStack {
                    TextField("Nachricht...", text: $Inputtext)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(UIColor.separator), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    
                    Button(action: {
                        Messages.append(Message(text: Inputtext))
                        Inputtext = ""
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBlue))
                                .frame(width: 40, height: 40)
                            Image(systemName: "arrow.up")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(user.username)
    }
}
