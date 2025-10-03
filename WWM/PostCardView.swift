//
//  PostCardView.swift
//  WWM
//
//  Created by F on 20.08.25.
//

import SwiftUI

struct PostCardView: View {
    let place: String
    let authorName: String
    let authorPfpBase64: String?
    let strain: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .foregroundStyle(Color("#1B4332"))

            VStack {
                Text(place)
                    .font(.headline)
                    .foregroundStyle(Color(hex: "#1A1A1A"))

                HStack {
                    Base64ImageView(
                        base64: authorPfpBase64 ?? UserDefaults.standard.string(forKey: "pfpBase64"),
                        size: 28,
                        cornerRadius: 14
                    )
                    Text(authorName)
                        .foregroundStyle(Color(hex: "#F8F9FA"))

                    Spacer()

                    Text(strain)
                        .foregroundStyle(Color(hex: "#EF476F"))
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

private extension View {
    @ViewBuilder
    func glassCodeCardEffectWithFallback() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
        } else {
            self
        }
    }
}

#Preview {
    PostCardView(
        place: "Ort",
        authorName: "Username",
        authorPfpBase64: nil,
        strain: "Sorte"
    )
}
