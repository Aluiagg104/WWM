//
//  ScannerScreen.swift
//  WWM
//
//  Created by Oliver Henkel on 22.08.25.
//

import SwiftUI
import AVFoundation

extension QRScannerView {
    static func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Fehler beim Setzen der Torch:", error.localizedDescription)
        }
    }
}

struct ScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    var onScanned: (String) -> Void

    @State private var torchOn = false
    @State private var hasScanned = false

    private let reticleSize: CGFloat = 260
    private let reticleCorner: CGFloat = 12

    var body: some View {
        ZStack {
            QRScannerView { value in
                guard !hasScanned else { return }
                hasScanned = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onScanned(value)
                dismiss()
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: reticleCorner, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .frame(width: reticleSize, height: reticleSize)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }

                    Spacer()

                    Button {
                        torchOn.toggle()
                        QRScannerView.setTorch(torchOn)
                    } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title2)
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Spacer()
            }
            .foregroundStyle(.white)
            .allowsHitTesting(true)

            VStack {
                Spacer()
                Text("Richte die Kamera auf einen QR-Code")
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
            .foregroundStyle(.white)
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }
}

