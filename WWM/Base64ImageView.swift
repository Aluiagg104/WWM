//
//  Base64ImageView.swift.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import SwiftUI
import UIKit

struct Base64ImageView: View {
    let base64: String?
    var size: CGFloat = 120
    var cornerRadius: CGFloat = 999 // macht's kreisrund

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: base64) {
            guard let base64, !base64.isEmpty else { return }
            isLoading = true
            defer { isLoading = false }
            uiImage = await decodeBase64ToImageAsync(base64)
        }
    }
}
