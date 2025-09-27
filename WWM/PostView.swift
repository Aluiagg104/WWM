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
                                Button { pickedImage = nil } label: {
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
                    Text("Beschreibung").font(.headline)
                    TextField("Was gibt’s?", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: caption) { newValue, _ in
                            if newValue.count > 250 { caption = String(newValue.prefix(250)) }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Standort").font(.headline)

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
                    Text(err).font(.footnote).foregroundStyle(.red)
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
                // Vorab leicht verkleinern (Performance & geringere Chunk-Anzahl)
                let downsized = uiImage.downscaledToFit(maxPixel: 2400)
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

        // Für Chunking genügt ein „normales“ JPEG – nicht zwingend < 1 MiB
        guard let data = img.jpegData(compressionQuality: 0.85) else {
            saveError = "Bild konnte nicht kodiert werden."
            return
        }
        let base64 = data.base64EncodedString()

        let lat = loc.lastLocation?.coordinate.latitude
        let lng = loc.lastLocation?.coordinate.longitude
        let address = loc.address

        do {
            try await FirestoreManager.shared.createPost(imageBase64: base64,
                                                         caption: caption.isEmpty ? nil : caption,
                                                         address: address,
                                                         lat: lat,
                                                         lng: lng)
            caption = ""
            pickedImage = nil
        } catch {
            saveError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
