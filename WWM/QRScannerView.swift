import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "qr.session.queue")
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var isConfigured = false
    private var permissionDenied = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestPermissionAndConfigureIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !permissionDenied else { return }
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    // MARK: Permission + Setup

    private func requestPermissionAndConfigureIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureOnce()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.configureOnce() }
                    else { self.permissionDenied = true; self.showDeniedLabel() }
                }
            }
        default:
            permissionDenied = true
            showDeniedLabel()
        }
    }

    private func configureOnce() {
        guard !isConfigured else { return }
        isConfigured = true

        sessionQueue.async { [weak self] in
            guard let self else { return }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Input
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                DispatchQueue.main.async { self.showError("Keine Kamera verfügbar") }
                return
            }
            session.addInput(input)

            // Output (QR)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                DispatchQueue.main.async { self.showError("Kamera-Output fehlgeschlagen") }
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            // Preview-Layer am Main-Thread
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                self.view.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
            }
        }
    }

    // MARK: Start/Stop (NICHT am Main-Thread!)

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: Delegate

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let layer = previewLayer,
              let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              first.type == .qr,
              let value = first.stringValue, !value.isEmpty,
              let transformed = layer.transformedMetadataObject(for: first) else { return }

        // Haptik & kurzer Visual-Ping (optional)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        ping(at: transformed.bounds)

        // Session stoppen und Callback
        stopSession()
        onCode?(value)
    }

    private func ping(at rect: CGRect) {
        let v = UIView(frame: rect)
        v.layer.borderColor = UIColor.systemGreen.cgColor
        v.layer.borderWidth = 3
        v.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.2)
        view.addSubview(v)
        UIView.animate(withDuration: 0.25, delay: 0.15, options: .curveEaseOut, animations: {
            v.alpha = 0
        }, completion: { _ in v.removeFromSuperview() })
    }

    // MARK: Fehler-Labels

    private func showDeniedLabel() { showError("Kamerazugriff verweigert.\nEinstellungen > Datenschutz > Kamera") }
    private func showError(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
    }
}
