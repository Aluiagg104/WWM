//
//  UIImage+Resize.swift
//  WWM
//

import UIKit

// MARK: - Globale Kompressions-Konfiguration
enum ImageCompressionConfig {
    /// Zielgröße der Base64-Daten (Standard: ~900 KiB)
    static var targetBase64Bytes: Int = 750 * 1024

    /// Start-Maximal-Kantenlänge (Pixel) vor der Qualitätsreduktion
    static var startMaxDim: CGFloat = 2400
    /// Untere Grenze für die Kantenlänge (Pixel)
    static var minMaxDim: CGFloat = 160
    /// Faktor, mit dem die Kantenlänge in jedem Schritt reduziert wird
    static var dimStep: CGFloat = 0.85

    /// Start-/Mindest-Qualität und Schrittweite für JPEG
    static var qualityStart: CGFloat = 0.95
    static var qualityMin: CGFloat = 0.30
    static var qualityStep: CGFloat = 0.10
}

extension UIImage {
    // Größe auf max. Kantenlänge skalieren (Seitenverhältnis bleibt)
    func downscaledToFit(maxPixel: CGFloat) -> UIImage {
        let w = size.width, h = size.height
        let maxSide = max(w, h)
        guard maxSide > maxPixel else { return self }

        let scale = maxPixel / maxSide
        let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // Base64-Größe ≈ 4 * ceil(n/3)
    private static func base64Size(of data: Data) -> Int {
        ((data.count + 2) / 3) * 4
    }

    // JPEG so komprimieren, dass Base64 <= Limit (lineare Qualitäts-Suche für Stabilität)
    private func jpegDataFittingBase64(maxBase64Bytes: Int,
                                       qualityStart: CGFloat,
                                       qualityMin: CGFloat,
                                       qualityStep: CGFloat) -> Data? {
        var q = qualityStart
        while q >= qualityMin {
            if let d = self.jpegData(compressionQuality: q),
               UIImage.base64Size(of: d) <= maxBase64Bytes {
                return d
            }
            q -= qualityStep
        }
        return nil
    }

    // MARK: - Hauptfunktion (parametrisierbar)
    /// Reduziert zuerst Qualität, dann Abmessungen, bis Base64 <= Limit.
    func base64UnderFirestoreLimit(maxBase64Bytes: Int,
                                   startMaxDim: CGFloat,
                                   minMaxDim: CGFloat,
                                   dimStep: CGFloat,
                                   qualityStart: CGFloat,
                                   qualityMin: CGFloat,
                                   qualityStep: CGFloat) -> String? {

        var maxDim = min(startMaxDim, max(size.width, size.height))
        var working = self.downscaledToFit(maxPixel: maxDim)

        while maxDim >= minMaxDim {
            if let ok = working.jpegDataFittingBase64(maxBase64Bytes: maxBase64Bytes,
                                                      qualityStart: qualityStart,
                                                      qualityMin: qualityMin,
                                                      qualityStep: qualityStep) {
                return ok.base64EncodedString()
            }
            let next = maxDim * dimStep
            if next < minMaxDim { break }
            maxDim = next
            working = working.downscaledToFit(maxPixel: maxDim)
        }

        // Notfall: minimal klein + minimale Qualität
        let tiny = self.downscaledToFit(maxPixel: minMaxDim)
        if let d = tiny.jpegData(compressionQuality: qualityMin),
           UIImage.base64Size(of: d) <= maxBase64Bytes {
            return d.base64EncodedString()
        }
        return nil
    }

    // MARK: - Bequemer Aufrufer (liest globale Config)
    /// Nutzt die Werte aus `ImageCompressionConfig`.
    func base64UnderFirestoreLimit() -> String? {
        base64UnderFirestoreLimit(
            maxBase64Bytes: ImageCompressionConfig.targetBase64Bytes,
            startMaxDim: ImageCompressionConfig.startMaxDim,
            minMaxDim: ImageCompressionConfig.minMaxDim,
            dimStep: ImageCompressionConfig.dimStep,
            qualityStart: ImageCompressionConfig.qualityStart,
            qualityMin: ImageCompressionConfig.qualityMin,
            qualityStep: ImageCompressionConfig.qualityStep
        )
    }

    // Optionaler Legacy-Wrapper (falls du ihn irgendwo nutzt)
    func base64Under950KB(limitBytes: Int = ImageCompressionConfig.targetBase64Bytes) -> String? {
        base64UnderFirestoreLimit(
            maxBase64Bytes: limitBytes,
            startMaxDim: ImageCompressionConfig.startMaxDim,
            minMaxDim: ImageCompressionConfig.minMaxDim,
            dimStep: ImageCompressionConfig.dimStep,
            qualityStart: ImageCompressionConfig.qualityStart,
            qualityMin: ImageCompressionConfig.qualityMin,
            qualityStep: ImageCompressionConfig.qualityStep
        )
    }
}
