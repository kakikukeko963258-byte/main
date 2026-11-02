import AVFoundation
import SwiftUI

final class RawCapture: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "main.raw.capture")
    private var device: AVCaptureDevice?
    private var configured = false
    private var wanted = false
    private var observers: [NSObjectProtocol] = []
    private var pendingData: Data?
    private var pendingError: Error?
    private var captureFormat = "RAW"
    private var received: ((Data, String, @escaping () -> Void) -> Void)?
    @Published var ready = false
    @Published var capturing = false
    @Published var message: String?
    @Published var lenses: [AVCaptureDevice] = []
    @Published var selectedLens = ""
    @Published var proRAWAvailable = false
    @Published var bayerAvailable = false
    @Published var useProRAW = false
    @Published var exposure: Float = 0
    @Published var exposureRange: ClosedRange<Float> = -2...2
    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
            self?.ready = false; self?.message = "カメラが一時停止しました。ほかのカメラ利用を終了して戻ってください。"
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in self?.resume() })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            self?.ready = false
            self?.message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "カメラエラーが発生しました。"
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start(received: @escaping (Data, String, @escaping () -> Void) -> Void) {
        self.received = received
        queue.async { self.wanted = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.configureAndStart() }
                else { DispatchQueue.main.async { self.message = "設定でカメラへのアクセスを許可してください。" } }
            }
        default: message = "設定でカメラへのアクセスを許可してください。"
        }
    }
    private func configureAndStart() {
        queue.async {
            guard self.wanted else { return }
            do {
                if !self.configured {
                    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera], mediaType: .video, position: .back).devices
                    guard let first = devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first else {
                        throw RawCameraError.message("この環境にはカメラがありません。RAW撮影には実機が必要です。")
                    }
                    let input = try AVCaptureDeviceInput(device: first)
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration(); throw RawCameraError.message("カメラを構成できません。")
                    }
                    self.session.addInput(input); self.session.addOutput(self.output)
                    self.device = first
                    if self.output.isAppleProRAWSupported { self.output.isAppleProRAWEnabled = true }
                    self.session.commitConfiguration()
                    self.configured = true
                    DispatchQueue.main.async { self.lenses = devices; self.selectedLens = first.uniqueID }
                }
                if !self.session.isRunning { self.session.startRunning() }
                self.publishCapabilities()
            } catch { DispatchQueue.main.async { self.ready = false; self.message = error.localizedDescription } }
        }
    }
    private func publishCapabilities() {
        let formats = output.availableRawPhotoPixelFormatTypes
        let bayer = formats.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        let pro = formats.contains { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
        let low = max(-3, device?.minExposureTargetBias ?? -2)
        let high = min(3, device?.maxExposureTargetBias ?? 2)
        DispatchQueue.main.async {
            self.bayerAvailable = bayer
            self.proRAWAvailable = pro
            if !bayer && pro { self.useProRAW = true }
            if !pro { self.useProRAW = false }
            self.ready = !formats.isEmpty
            self.message = formats.isEmpty ? "このレンズはRAW撮影に対応していません。別のレンズを選択してください。" : nil
            self.exposureRange = min(low, high)...max(low, high)
        }
    }
    func stop() { queue.async { self.wanted = false; if self.session.isRunning { self.session.stopRunning() } } }
    func resume() { queue.async { if self.wanted { self.configureAndStart() } } }
    func select(_ lens: AVCaptureDevice) {
        guard !capturing else { return }
        ready = false
        queue.async {
            do {
                let next = try AVCaptureDeviceInput(device: lens)
                self.session.beginConfiguration()
                let previous = self.session.inputs
                previous.forEach { self.session.removeInput($0) }
                guard self.session.canAddInput(next) else {
                    previous.forEach { if self.session.canAddInput($0) { self.session.addInput($0) } }
                    self.session.commitConfiguration()
                    throw RawCameraError.message("レンズを切り替えられません。")
                }
                self.session.addInput(next); self.device = lens
                if self.output.isAppleProRAWSupported { self.output.isAppleProRAWEnabled = true }
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.selectedLens = lens.uniqueID; self.exposure = 0 }
                self.setExposure(0); self.publishCapabilities()
            } catch { self.publishCapabilities(); DispatchQueue.main.async { self.message = error.localizedDescription } }
        }
    }
    func setExposure(_ value: Float) {
        queue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(min(device.maxExposureTargetBias, max(device.minExposureTargetBias, value)))
                device.unlockForConfiguration()
            } catch { DispatchQueue.main.async { self.message = error.localizedDescription } }
        }
    }
    func focus(_ point: CGPoint) {
        queue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                }
                device.unlockForConfiguration()
            } catch { DispatchQueue.main.async { self.message = error.localizedDescription } }
        }
    }
    func capture() {
        guard ready, !capturing else { return }
        capturing = true
        let pro = useProRAW
        queue.async {
            let formats = self.output.availableRawPhotoPixelFormatTypes
            let chosen = formats.first(where: { pro ? AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) : AVCapturePhotoOutput.isBayerRAWPixelFormat($0) })
            guard let format = chosen else {
                DispatchQueue.main.async { self.capturing = false; self.message = "選択したRAW形式はこのレンズで利用できません。" }; return
            }
            self.captureFormat = AVCapturePhotoOutput.isAppleProRAWPixelFormat(format) ? "ProRAW" : "RAW"
            self.pendingData = nil; self.pendingError = nil
            let settings = AVCapturePhotoSettings(rawPixelFormatType: format)
            settings.flashMode = .off
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { pendingError = error }
        if photo.isRawPhoto { pendingData = photo.fileDataRepresentation() }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let data = pendingData; let failure = error ?? pendingError; let format = captureFormat
        pendingData = nil; pendingError = nil
        DispatchQueue.main.async {
            if let failure { self.message = failure.localizedDescription; self.capturing = false }
            else if let data, let received = self.received {
                received(data, format) { DispatchQueue.main.async { self.capturing = false } }
            } else { self.message = "RAWデータを取得できませんでした。"; self.capturing = false }
        }
    }
}

final class RawPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onFocus?(preview.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}
struct RawCameraPreview: UIViewRepresentable {
    let camera: RawCapture
    func makeUIView(context: Context) -> RawPreviewUIView {
        let view = RawPreviewUIView()
        view.preview.session = camera.session; view.preview.videoGravity = .resizeAspect
        view.onFocus = { camera.focus($0) }
        return view
    }
    func updateUIView(_ view: RawPreviewUIView, context: Context) {}
}
