//
//  PostView.swift
//  WWM
//
//  Created by Oliver Henkel on 31.08.25.
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
    @State private var showSettingsHint = false

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
                        .onChange(of: selectedItem) { _, newItem in
                            Task { await loadPickedImage(from: newItem) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beschreibung")
                        .font(.headline)
                    TextField("Was gibt’s?", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: caption) { newValue, oldValue in
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
                let downsized = uiImage.downscaledToFit(maxPixel: 1280)
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

        guard let base64 = img.base64UnderLimit() else {
            saveError = "Bild ist zu groß. Bitte ein kleineres Bild wählen."
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

fileprivate extension UIImage {
    func downscaledToFit(maxPixel: CGFloat) -> UIImage {
        let w = size.width, h = size.height
        let scale = min(maxPixel / max(w, h), 1)
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func jpegBase64(quality: CGFloat) -> String? {
        guard let data = self.jpegData(compressionQuality: quality) else { return nil }
        return data.base64EncodedString()
    }
}

fileprivate enum FirestoreImageLimit {
    static let maxBase64Bytes = 950_000
    static let initialMaxDimension: CGFloat = 1600
}

fileprivate extension UIImage {
    func base64UnderLimit() -> String? {
        var maxDim = FirestoreImageLimit.initialMaxDimension
        for _ in 0..<4 {
            let resized = self.downscaledToFit(maxPixel: maxDim)
            if let data = resized.jpegDataFittingBase64(maxBase64Bytes: FirestoreImageLimit.maxBase64Bytes) {
                return data.base64EncodedString()
            }
            maxDim *= 0.85
        }
        return nil
    }

    func jpegDataFittingBase64(maxBase64Bytes: Int) -> Data? {
        var low: CGFloat = 0.1
        var high: CGFloat = 0.95
        var best: Data?

        if let d = self.jpegData(compressionQuality: high),
           Self.base64Size(of: d) <= maxBase64Bytes {
            return d
        }

        for _ in 0..<8 {
            let q = (low + high) / 2
            guard let d = self.jpegData(compressionQuality: q) else { break }
            let b64 = Self.base64Size(of: d)
            if b64 > maxBase64Bytes {
                high = max(q - 0.05, 0.01)
            } else {
                best = d
                low = min(q + 0.05, 0.99)
            }
        }
        return best
    }

    private static func base64Size(of data: Data) -> Int {
        return ((data.count + 2) / 3) * 4
        }
}
