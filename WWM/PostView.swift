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

private let kStrainsUDKey = "local_strains"
private let kAddStrainToken = "__add_strain__"

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

    // MARK: Sorte (lokal via UserDefaults)

    @State private var strains: [String] = []
    @State private var selectedStrain: String = ""
    @State private var lastValidSelection: String = ""
    @State private var showAddStrainSheet = false
    @State private var newStrainName: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Bild
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

                // Sorte
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sorte").font(.headline)

                    Picker("Sorte", selection: $selectedStrain) {
                        // Auswahl aus lokalen Sorten
                        ForEach(strains, id: \.self) { s in
                            Text(s).tag(s)
                        }
                        // Trennlinie + „Hinzufügen…“
                        if !strains.isEmpty { Divider() }
                        Text("➕ Neue Sorte hinzufügen…").tag(kAddStrainToken)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedStrain) { _, newValue in
                        if newValue == kAddStrainToken {
                            // zurückspringen auf vorherige, dann Sheet öffnen
                            selectedStrain = lastValidSelection
                            showAddStrainSheet = true
                            newStrainName = ""
                        } else {
                            lastValidSelection = newValue
                        }
                    }

                    if selectedStrain.isEmpty {
                        Text("Bitte eine Sorte wählen oder hinzufügen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // Beschreibung
                VStack(alignment: .leading, spacing: 8) {
                    Text("Beschreibung").font(.headline)
                    TextField("Was gibt’s?", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: caption) { newValue, _ in
                            if newValue.count > 250 { caption = String(newValue.prefix(250)) }
                        }
                }

                // Standort
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

                // Speichern
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
                .disabled(isSaving || pickedImage == nil || selectedStrain.isEmpty)

                if let err = saveError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Neuer Post")
        .onAppear { loadLocalStrains() }
        .sheet(isPresented: $showAddStrainSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Neue Sorte hinzufügen")
                        .font(.title3.weight(.semibold))

                    TextField("z. B. Blue Haze", text: $newStrainName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    Spacer()

                    HStack {
                        Button("Abbrechen") { showAddStrainSheet = false }
                        Spacer()
                        Button("Hinzufügen") {
                            addNewStrain()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newStrainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { showAddStrainSheet = false }
                    }
                }
            }
        }
    }

    // MARK: - Strain Helpers (UserDefaults)

    private func loadLocalStrains() {
        if let arr = UserDefaults.standard.array(forKey: kStrainsUDKey) as? [String],
           !arr.isEmpty {
            strains = arr
        } else {
            // ein paar Defaults
            strains = ["Blue Haze", "Amnesia Haze", "OG Kush"]
            UserDefaults.standard.set(strains, forKey: kStrainsUDKey)
        }
        selectedStrain = strains.first ?? ""
        lastValidSelection = selectedStrain
    }

    private func addNewStrain() {
        let clean = newStrainName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard !clean.isEmpty else { return }
        if !strains.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            strains.insert(clean, at: 0)
            UserDefaults.standard.set(strains, forKey: kStrainsUDKey)
        }
        selectedStrain = clean
        lastValidSelection = clean
        showAddStrainSheet = false
    }

    // MARK: - Bild laden & speichern

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

        guard let data = img.jpegData(compressionQuality: 0.85) else {
            saveError = "Bild konnte nicht kodiert werden."
            return
        }
        let base64 = data.base64EncodedString()

        let lat = loc.lastLocation?.coordinate.latitude
        let lng = loc.lastLocation?.coordinate.longitude
        let address = loc.address
        let strain = selectedStrain

        do {
            try await FirestoreManager.shared.createPost(
                imageBase64: base64,
                caption: caption.isEmpty ? nil : caption,
                address: address,
                lat: lat,
                lng: lng,
                strain: strain     // ⬅️ NEU
            )
            caption = ""
            pickedImage = nil
        } catch {
            saveError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
