//
//  ImageUtils.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import UIKit   // reicht hier völlig

/// JPEG -> Base64 (vorher verkleinern & komprimieren)
func imageToBase64JPEG(_ image: UIImage, quality: CGFloat = 0.7, maxDimension: CGFloat = 1280) -> String? {
    let scaledImage = image.scaled(maxDimension: maxDimension)
    guard let data = scaledImage.jpegData(compressionQuality: quality) else { return nil }
    return data.base64EncodedString()
}

/// Base64 -> UIImage
func stringToImage(_ str: String) -> UIImage? {
    guard let data = Data(base64Encoded: str) else { return nil }
    return UIImage(data: data)
}

func decodeBase64ToImageAsync(_ base64: String) async -> UIImage? {
    // Cache-Hit?
    if let cached = ImageCache.shared.object(forKey: base64 as NSString) {
        return cached
    }

    // CPU-Arbeit vom Main-Thread lösen
    return await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = Data(base64Encoded: base64),
                  let image = UIImage(data: data) else {
                cont.resume(returning: nil)
                return
            }
            ImageCache.shared.setObject(image, forKey: base64 as NSString)
            cont.resume(returning: image)
        }
    }
}

