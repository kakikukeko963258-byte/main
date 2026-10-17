import SwiftUI
import VisionKit
import AVFoundation

struct PairingQRScanner: UIViewControllerRepresentable {
    let completion: (Result<String, Error>) -> Void
    func makeUIViewController(context: Context) -> PairingQRScannerController {
        let controller = PairingQRScannerController()
        controller.completion = completion
        return controller
    }
    func updateUIViewController(_ controller: PairingQRScannerController, context: Context) {}
}

final class PairingQRScannerController: UIViewController, DataScannerViewControllerDelegate {
    var completion: ((Result<String, Error>) -> Void)?
    private var scanner: DataScannerViewController?
    private var started = false
    private var completed = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { @MainActor in
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard view.window != nil else { return }
            guard allowed else { finish(.failure(ScannerError.cameraDenied)); return }
            guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
                finish(.failure(ScannerError.unavailable)); return
            }
            let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
            scanner.delegate = self
            self.scanner = scanner
            addChild(scanner)
            scanner.view.frame = view.bounds
            scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scanner.view)
            scanner.didMove(toParent: self)
            do { try scanner.startScanning() }
            catch { finish(.failure(ScannerError.unavailable)) }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        scanner?.stopScanning()
        super.viewWillDisappear(animated)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        for case .barcode(let barcode) in addedItems {
            if let value = barcode.payloadStringValue { finish(.success(value)); return }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard !completed else { return }
        completed = true
        scanner?.stopScanning()
        completion?(result)
    }
}

private enum ScannerError: LocalizedError {
    case cameraDenied, unavailable
    var errorDescription: String? {
        switch self {
        case .cameraDenied: return "カメラが許可されていません。iPhoneの設定でmainのカメラを許可してください。"
        case .unavailable: return "この端末ではQRカメラを利用できません。設定ファイルから接続してください。"
        }
    }
}
