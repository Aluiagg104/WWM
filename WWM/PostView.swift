//
//  PostView.swift
//  WWM
//

import SwiftUI
import Foundation
import CoreLocation
import Combine
import CoreLocationUI
import PhotosUI
import UIKit

final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published var lastLocation: CLLocation?
    @Published var address: String?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            errorMessage = "Kein Zugriff auf den Standort. Erteile die Berechtigung in den Einstellungen."
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            break
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        errorMessage = nil

        Task {
            do {
                let marks = try await geocoder.reverseGeocodeLocation(loc)
                if let p = marks.first {
                    let text = [p.name, p.locality, p.postalCode, p.country]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    await MainActor.run { self.address = text }
                } else {
                    await MainActor.run { self.address = "Adresse unbekannt" }
                }
            } catch {
                await MainActor.run { self.address = "Adresse unbekannt" }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

struct PostView: View {
    @StateObject private var loc = LocationService()

    @State private var caption: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var isSaving = false
    @State private var saveError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    if let img = pickedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    pickedImage = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.hierarchical)
                                }
                                .padding(8)
                            }
                    } else {
                        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Foto auswählen")
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .onChange(of: selectedItem) { newItem in
                            Task { await loadPickedImage(from: newItem) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beschreibung")
                        .font(.headline)
                    TextField("Was gibt’s?", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: caption) { newValue in
                            if newValue.count > 250 { caption = String(newValue.prefix(250)) }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Standort")
                        .font(.headline)

                    Text(loc.address ?? "Adresse wird ermittelt …")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Button {
                            loc.requestCurrentLocation()
                        } label: {
                            Label("Aktuellen Standort abrufen", systemImage: "location")
                        }
                        .buttonStyle(.bordered)

                        if loc.authorization == .denied || loc.authorization == .restricted {
                            Button("Einstellungen") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Button {
                    Task { await savePost() }
                } label: {
                    if isSaving {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Label("Post erstellen", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || pickedImage == nil)

                if let err = saveError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Neuer Post")
    }

    private func loadPickedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                // Vorab leicht verkleinern, damit nachfolgende Kompression weniger Arbeit hat
                let downsized = uiImage.downscaledToFit(maxPixel: 2048)
                await MainActor.run { pickedImage = downsized }
            }
        } catch {
            await MainActor.run { saveError = "Bild konnte nicht geladen werden." }
        }
    }

    private func savePost() async {
        guard let img = pickedImage else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        
        guard let base64 = img.base64Under950KB() else {
            saveError = "Bild ist zu groß/komplex. Bitte ein anderes Bild wählen."
            return
        }

        let lat = loc.lastLocation?.coordinate.latitude
        let lng = loc.lastLocation?.coordinate.longitude
        let address = loc.address

        do {
            try await FirestoreManager.shared.createPost(
                imageBase64: base64,
                caption: caption.isEmpty ? nil : caption,
                address: address,
                lat: lat,
                lng: lng
            )
            caption = ""
            pickedImage = nil
        } catch {
            saveError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

// MARK: - Image helpers

fileprivate extension UIImage {

    // Downscale auf eine maximale Kantenlänge (erhält Seitenverhältnis)
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

    // Base64-Größe (≈ 4 * ceil(n/3))
    static func base64Size(of data: Data) -> Int {
        ((data.count + 2) / 3) * 4
    }

    /// Reduziert zuerst JPEG-Qualität, danach Dimensionen – prüft nach JEDEM Schritt,
    /// ob Base64 < 950 KB ist. Wiederholt, bis es passt oder Grenzen erreicht sind.
    func base64Under950KB(startMaxDim: CGFloat = 2400,
                          minMaxDim: CGFloat = 160,
                          dimStep: CGFloat = 0.85,
                          qualityStart: CGFloat = 0.95,
                          qualityMin: CGFloat = 0.30,
                          qualityStep: CGFloat = 0.10,
                          limitBytes: Int = 950_000) -> String? {

        var maxDim = min(startMaxDim, max(size.width, size.height))
        var workingImage = self.downscaledToFit(maxPixel: maxDim)

        while maxDim >= minMaxDim {
            // 1) Qualität schrittweise senken und jedes Mal Größe prüfen
            var q = qualityStart
            while q >= qualityMin {
                if let data = workingImage.jpegData(compressionQuality: q),
                   UIImage.base64Size(of: data) <= limitBytes {
                    return data.base64EncodedString()
                }
                q -= qualityStep
            }

            // 2) Wenn immer noch zu groß: Dimension weiter verkleinern und erneut versuchen
            let nextDim = maxDim * dimStep
            if nextDim < minMaxDim { break }
            maxDim = nextDim
            workingImage = workingImage.downscaledToFit(maxPixel: maxDim)
        }

        // Notfall: ganz klein + minimale Qualität
        let tiny = self.downscaledToFit(maxPixel: minMaxDim)
        if let d = tiny.jpegData(compressionQuality: max(0.01, qualityMin)),
           UIImage.base64Size(of: d) <= limitBytes {
            return d.base64EncodedString()
        }
        return nil
    }
}
