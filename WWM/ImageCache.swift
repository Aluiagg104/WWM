//
//  ImageCache.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import UIKit

final class ImageCache {
    static let shared = NSCache<NSString, UIImage>()
}
