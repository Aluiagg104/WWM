import SwiftUI
import Foundation
import CoreLocation
import Combine
import CoreLocationUI
import PhotosUI
import UIKit

private let kStrainsUDKey = "local_strains"
private let kAddStrainToken = "add_strain"

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
                    let text = [p.name, p.locality, p.postalCode, p.country].compactMap { $0 }.joined(separator: ", ")
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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var loc = LocationService()
    @State private var caption: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var strains: [String] = []
    @State private var selectedStrain: String = ""
    @State private var lastValidSelection: String = ""
    @State private var showAddStrainSheet = false
    @State private var newStrainName: String = ""
    @FocusState private var captionFocused: Bool
    @Namespace private var glassNS

    var body: some View {
        ZStack {
            LightLiquidBackground()
            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                StrainPickerPill(
                                    strains: $strains,
                                    selectedStrain: $selectedStrain,
                                    lastValidSelection: $lastValidSelection,
                                    showAddStrainSheet: $showAddStrainSheet,
                                    newStrainName: $newStrainName
                                )
                                Spacer()
                                Text(loc.address ?? "Adresse wird ermittelt …")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(14)
                            Divider().opacity(0.08)
                            VStack(spacing: 14) {
                                ZStack {
                                    if let img = pickedImage {
                                        let corner: CGFloat = 12
                                        Image(uiImage: img)
                                            .resizable()
                                            .aspectRatio(img.size, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                            .frame(maxHeight: 420)
                                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                                            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                                            .contextMenu { Button("Bild entfernen") { pickedImage = nil } }
                                            .padding(.horizontal, 14)
                                    } else {
                                        GlassCard(cornerRadius: 12) {
                                            PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                                                VStack(spacing: 10) {
                                                    Image(systemName: "photo.on.rectangle")
                                                        .font(.system(size: 30, weight: .semibold))
                                                    Text("Foto hinzufügen")
                                                        .font(.subheadline.weight(.semibold))
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 220)
                                                .contentShape(Rectangle())
                                            }
                                            .onChange(of: selectedItem) { _, newItem in
                                                Task { await loadPickedImage(from: newItem) }
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                    }
                                }
                                if #available(iOS 26.0, *) {
                                    GlassEffectContainer {
                                        TextField("Schreibe eine Beschreibung …", text: $caption, axis: .vertical)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                                            .foregroundStyle(.primary)
                                            .focused($captionFocused)
                                            .submitLabel(.done)
                                    }
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12, style: .continuous))
                                    .glassEffectID("captionField", in: glassNS)
                                    .padding(.horizontal, 14)
                                } else {
                                    TextField("Schreibe eine Beschreibung …", text: $caption, axis: .vertical)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .focused($captionFocused)
                                        .submitLabel(.done)
                                        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.7))
                                        .padding(.horizontal, 14)
                                }
                            }
                            .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)

                    GlassCard {
                        VStack(spacing: 10) {
                            if #available(iOS 26.0, *) {
                                Button {
                                    Task { await savePost() }
                                } label: {
                                    Label("Post erstellen", systemImage: "paperplane.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                                .disabled(isSaving || pickedImage == nil || selectedStrain.isEmpty)
                            } else {
                                Button {
                                    Task { await savePost() }
                                } label: {
                                    Label("Post erstellen", systemImage: "paperplane.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSaving || pickedImage == nil || selectedStrain.isEmpty)
                            }
                            if isSaving {
                                ProgressView().progressViewStyle(.circular)
                            }
                            if let err = saveError {
                                Text(err).font(.footnote).foregroundStyle(.red)
                            }
                        }
                        .padding(10)
                    }
                    .padding(.horizontal, 22)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Neuer Post")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    captionFocused = false
                } label: {
                    Label("Fertig", systemImage: "keyboard.chevron.compact.down")
                }
            }
        }
        .onAppear {
            loadLocalStrains()
            loc.requestCurrentLocation()
        }
        .sheet(isPresented: $showAddStrainSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Neue Sorte hinzufügen")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    GlassCard(cornerRadius: 12) {
                        TextField("z. B. Blue Haze", text: $newStrainName)
                            .textInputAutocapitalization(.words)
                            .padding(10)
                    }
                    Spacer()
                    HStack {
                        Button("Abbrechen") { showAddStrainSheet = false }
                        Spacer()
                        if #available(iOS 26.0, *) {
                            Button("Hinzufügen") { addNewStrain() }
                                .buttonStyle(.glass)
                                .disabled(newStrainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            Button("Hinzufügen") { addNewStrain() }
                                .buttonStyle(.borderedProminent)
                                .disabled(newStrainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
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

    private func loadLocalStrains() {
        if let arr = UserDefaults.standard.array(forKey: kStrainsUDKey) as? [String], !arr.isEmpty {
            strains = arr
        } else {
            strains = ["Blue Haze", "Amnesia Haze", "OG Kush"]
            UserDefaults.standard.set(strains, forKey: kStrainsUDKey)
        }
        selectedStrain = strains.first ?? ""
        lastValidSelection = selectedStrain
    }

    private func addNewStrain() {
        let clean = newStrainName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !clean.isEmpty else { return }
        if !strains.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            strains.insert(clean, at: 0)
            UserDefaults.standard.set(strains, forKey: kStrainsUDKey)
        }
        selectedStrain = clean
        lastValidSelection = clean
        showAddStrainSheet = false
    }

    private func loadPickedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let downsized = await downscaleImageData(data, maxDimension: 2400)
                await MainActor.run { pickedImage = downsized }
            }
        } catch {
            await MainActor.run { saveError = "Bild konnte nicht geladen werden." }
        }
    }

    private func savePost() async {
        guard let img = pickedImage else { return }
        await MainActor.run {
            isSaving = true
            saveError = nil
        }
        defer {
            Task { await MainActor.run { isSaving = false } }
        }
        guard let base64 = await makeBase64JPEG(from: img, quality: 0.85) else {
            await MainActor.run { saveError = "Bild konnte nicht kodiert werden." }
            return
        }
        let lat = loc.lastLocation?.coordinate.latitude
        let lng = loc.lastLocation?.coordinate.longitude
        let address = loc.address
        let strain = selectedStrain
        do {
            try await FirestoreManager.shared.createPost(imageBase64: base64, caption: caption.isEmpty ? nil : caption, address: address, lat: lat, lng: lng, strain: strain)
            await MainActor.run {
                caption = ""
                pickedImage = nil
            }
        } catch {
            await MainActor.run { saveError = "Speichern fehlgeschlagen: \(error.localizedDescription)" }
        }
    }

    private func downscaleImageData(_ data: Data, maxDimension: CGFloat) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let uiImage = UIImage(data: data) else {
                    cont.resume(returning: nil)
                    return
                }
                let scaled = scaleImage(uiImage, maxDimension: maxDimension)
                cont.resume(returning: scaled)
            }
        }
    }

    private func makeBase64JPEG(from image: UIImage, quality: CGFloat) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = image.jpegData(compressionQuality: quality) else {
                    cont.resume(returning: nil)
                    return
                }
                let base64 = data.base64EncodedString()
                cont.resume(returning: base64)
            }
        }
    }

    private func scaleImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxDimension / max(size.width, size.height), 1)
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private struct StrainPickerPill: View {
    @Binding var strains: [String]
    @Binding var selectedStrain: String
    @Binding var lastValidSelection: String
    @Binding var showAddStrainSheet: Bool
    @Binding var newStrainName: String

    var body: some View {
        Menu {
            Picker("Sorte", selection: $selectedStrain) {
                ForEach(strains, id: \.self) { s in
                    Text(s).tag(s)
                }
                if !strains.isEmpty { Divider() }
                Text("➕ Neue Sorte hinzufügen…").tag(kAddStrainToken)
            }
        } label: {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill").imageScale(.small)
                        Text(selectedStrain.isEmpty ? "Sorte wählen" : selectedStrain).lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill").imageScale(.small)
                    Text(selectedStrain.isEmpty ? "Sorte wählen" : selectedStrain).lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.6))
            }
        }
        .onChange(of: selectedStrain) { _, v in
            if v == kAddStrainToken {
                selectedStrain = lastValidSelection
                showAddStrainSheet = true
                newStrainName = ""
            } else {
                lastValidSelection = v
            }
        }
    }
}

private struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    VStack(spacing: 0) {
                        content()
                    }
                    .padding(14)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
                }
            } else {
                VStack(spacing: 0) {
                    content()
                }
                .padding(14)
                .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.7))
            }
        }
    }
}

struct LightLiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.09, green: 0.11, blue: 0.12), Color(red: 0.06, green: 0.08, blue: 0.09)]
                    : [Color("#F7FFFB"), .white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            blob(color: Color("#55A630").opacity(colorScheme == .dark ? 0.18 : 0.12), size: 420, x: -140, y: -180, blur: 90)
            blob(color: Color("#EF476F").opacity(colorScheme == .dark ? 0.14 : 0.10), size: 360, x: 160, y: -120, blur: 110)
            blob(color: Color.blue.opacity(colorScheme == .dark ? 0.12 : 0.08), size: 460, x: 80, y: 300, blur: 130)
        }
    }

    private func blob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat, blur: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }
}

private extension View {
    @ViewBuilder
    func glassFieldFallback(cornerRadius: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self
                .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.7))
        }
    }
}
