//
//  QrCodeView.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let text: String  // hier übergibst du die UID
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let img = generateQRCode(from: text) {
            Image(uiImage: img)
                .interpolation(.none)   // keine Weichzeichnung
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding()
                .background(.white)     // QR mag starken Kontrast
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 4)
        } else {
            Text("QR konnte nicht erzeugt werden")
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage else { return nil }
        // Hochskalieren, damit es scharf bleibt
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        if let cg = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}

