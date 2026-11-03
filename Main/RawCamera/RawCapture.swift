import AVFoundation
import SwiftUI
import ImageIO

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
    private var received: ((Data, String, RawCaptureMetadata, @escaping () -> Void) -> Void)?
    private var pendingMetadata: RawCaptureMetadata?
    private var requestedPixels: Int64 = 0
    private var maximum = CMVideoDimensions(width: 0, height: 0)
    @Published var ready = false
    @Published var capturing = false
    @Published var message: String?
    @Published var lenses: [AVCaptureDevice] = []
    @Published var selectedLens = ""
    @Published var proRAWAvailable = false
    @Published var bayerAvailable = false
    @Published var useProRAW = false
    @Published var mode = "RAW"
    @Published var requestedMP = UserDefaults.standard.object(forKey: "raw-megapixels") as? Int ?? 48
    @Published var supports48 = false
    @Published var resolutionText = ""
    @Published var focusLocked = false
    @Published var lastCapture: RawCaptureMetadata?
    @Published var lastCaptureWarning: String?
    @Published var zoom: CGFloat = 1
    @Published var flash = false
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
    func start(received: @escaping (Data, String, RawCaptureMetadata, @escaping () -> Void) -> Void) {
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
                    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera], mediaType: .video, position: .unspecified).devices
                    let saved = UserDefaults.standard.string(forKey: "raw-default-lens")
                    guard let first = devices.first(where: { $0.uniqueID == saved }) ?? devices.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }) ?? devices.first else {
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
                    self.configureResolution()
                    self.session.commitConfiguration()
                    self.configured = true
                    let initialMode = UserDefaults.standard.string(forKey: "raw-capture-mode")
                    let pro = self.output.isAppleProRAWEnabled
                    let high = Int64(self.maximum.width) * Int64(self.maximum.height) >= 45_000_000
                    DispatchQueue.main.async {
                        self.mode = initialMode ?? (high ? (pro ? "ProRAW" : "HEIC") : "RAW")
                    }
                    DispatchQueue.main.async { self.lenses = devices; self.selectedLens = first.uniqueID }
                }
                if !self.session.isRunning { self.session.startRunning() }
                self.publishCapabilities()
            } catch { DispatchQueue.main.async { self.ready = false; self.message = error.localizedDescription } }
        }
    }
    private func configureResolution() {
        guard let device else { return }
        // Configure the sensor and output before starting the capture session.
        let currentMax = device.activeFormat.supportedMaxPhotoDimensions.map { Int64($0.width) * Int64($0.height) }.max() ?? 0
        if currentMax < 45_000_000,
           let format = device.formats.filter({ CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange })
            .max(by: { ($0.supportedMaxPhotoDimensions.map { Int64($0.width) * Int64($0.height) }.max() ?? 0) < ($1.supportedMaxPhotoDimensions.map { Int64($0.width) * Int64($0.height) }.max() ?? 0) }),
           (format.supportedMaxPhotoDimensions.map { Int64($0.width) * Int64($0.height) }.max() ?? 0) > currentMax {
            do { try device.lockForConfiguration(); device.activeFormat = format; device.unlockForConfiguration() }
            catch { DispatchQueue.main.async { self.message = error.localizedDescription } }
        }
        if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = true }
        output.maxPhotoQualityPrioritization = .quality
        if let size = device.activeFormat.supportedMaxPhotoDimensions.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
            maximum = size; output.maxPhotoDimensions = size
        }
    }
    private func publishCapabilities() {
        let formats = output.availableRawPhotoPixelFormatTypes
        let bayer = formats.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        let pro = formats.contains { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
        let high = Int64(maximum.width) * Int64(maximum.height) >= 45_000_000
        let low = max(-3, device?.minExposureTargetBias ?? -2)
        let upper = min(3, device?.maxExposureTargetBias ?? 2)
        let running = session.isRunning
        DispatchQueue.main.async {
            self.bayerAvailable = bayer; self.proRAWAvailable = pro; self.supports48 = high
            if self.mode == "RAW" && !bayer { self.mode = pro ? "ProRAW" : "HEIC" }
            if self.mode == "ProRAW" && !pro { self.mode = bayer ? "RAW" : "HEIC" }
            self.useProRAW = self.mode == "ProRAW"
            self.ready = running && (!formats.isEmpty || !self.output.availablePhotoCodecTypes.isEmpty)
            self.message = self.ready ? nil : "この環境ではカメラを利用できません。"
            self.exposureRange = min(low, upper)...max(low, upper)
            self.updateResolutionLabel()
        }
    }
    func setMode(_ value: String) {
        guard !capturing else { return }
        mode = value; useProRAW = value == "ProRAW"
        UserDefaults.standard.set(value, forKey: "raw-capture-mode"); updateResolutionLabel()
    }
    func setMegapixels(_ value: Int) {
        requestedMP = value; UserDefaults.standard.set(value, forKey: "raw-megapixels"); updateResolutionLabel()
    }
    private func updateResolutionLabel() {
        let mp = (supports48 && requestedMP == 48) ? 48 : min(12, max(1, Int((Double(maximum.width) * Double(maximum.height) / 1_000_000).rounded())))
        resolutionText = (mode == "RAW" && mp == 48) ? "最大48MP" : "\(mp)MP"
    }
    func switchCamera() {
        guard let current = lenses.first(where: { $0.uniqueID == selectedLens }),
              let next = lenses.first(where: { $0.position != current.position && $0.deviceType == .builtInWideAngleCamera }) else { return }
        select(next)
    }
    func setZoom(_ value: CGFloat) {
        guard !capturing else { return }
        zoom = value
        queue.async {
            guard let device = self.device else { return }
            do { try device.lockForConfiguration(); device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, value)); device.unlockForConfiguration() }
            catch { DispatchQueue.main.async { self.message = error.localizedDescription } }
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
                self.configureResolution()
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.selectedLens = lens.uniqueID; self.exposure = 0; self.zoom = 1; self.focusLocked = false }
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
    func focus(_ point: CGPoint, locked: Bool = false) {
        focusLocked = locked
        queue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(locked ? .locked : .autoFocus) { device.focusMode = locked ? .locked : .autoFocus }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(locked ? .locked : .continuousAutoExposure) { device.exposureMode = locked ? .locked : .continuousAutoExposure }
                }
                device.unlockForConfiguration()
            } catch { DispatchQueue.main.async { self.message = error.localizedDescription } }
        }
    }
    func capture() {
        guard ready, !capturing else { return }
        capturing = true
        let selectedMode = mode, requested = requestedMP, useFlash = flash
        queue.async {
            guard let device = self.device else { DispatchQueue.main.async { self.capturing = false }; return }
            let settings: AVCapturePhotoSettings
            if selectedMode == "HEIC" {
                let codec: AVVideoCodecType = self.output.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
                self.captureFormat = codec == .hevc ? "HEIC" : "JPEG"
            } else {
                let chosen = self.output.availableRawPhotoPixelFormatTypes.first { selectedMode == "ProRAW" ? AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) : AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
                guard let format = chosen else {
                    DispatchQueue.main.async { self.capturing = false; self.message = "このレンズでは選択したRAW形式を利用できません。HEICまたは別のレンズを選択してください。" }; return
                }
                settings = AVCapturePhotoSettings(rawPixelFormatType: format)
                self.captureFormat = selectedMode
            }
            let dimensions = device.activeFormat.supportedMaxPhotoDimensions.sorted { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
            let size = (requested == 48) ? dimensions.last : (dimensions.first(where: { Int64($0.width) * Int64($0.height) >= 11_000_000 }) ?? dimensions.first)
            if let size { settings.maxPhotoDimensions = size }
            self.requestedPixels = requested == 48 ? 48_000_000 : 12_000_000
            settings.photoQualityPrioritization = .quality
            settings.flashMode = useFlash && self.output.supportedFlashModes.contains(.on) ? .on : .off
            self.pendingData = nil; self.pendingError = nil; self.pendingMetadata = nil
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = device.position == .front && (UserDefaults.standard.object(forKey: "raw-mirror-front") as? Bool ?? true) }
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { pendingError = error }
        if photo.isRawPhoto || captureFormat == "HEIC" || captureFormat == "JPEG" {
            pendingData = photo.fileDataRepresentation()
            let dimensions = photo.isRawPhoto ? photo.resolvedSettings.rawPhotoDimensions : photo.resolvedSettings.photoDimensions
            let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
            pendingMetadata = RawCaptureMetadata(width: Int(dimensions.width), height: Int(dimensions.height),
                iso: (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue,
                seconds: (exif?[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue,
                aperture: (exif?[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue, lens: device?.localizedName)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let metadata = pendingMetadata ?? RawCaptureMetadata(width: 0, height: 0)
        let data = pendingData; let failure = error ?? pendingError; let format = captureFormat
        pendingData = nil; pendingError = nil
        DispatchQueue.main.async {
            if let failure { self.message = failure.localizedDescription; self.capturing = false }
            else if let data, let received = self.received {
                self.lastCapture = metadata
                if self.requestedPixels >= 45_000_000 && metadata.megapixels < 45 {
                    self.lastCaptureWarning = String(format: "保存した写真は%.1fMP（%d × %d）です。この機種・レンズ・形式では48MPで保存されませんでした。48MP対応時はHEICまたはProRAWを選択してください。", metadata.megapixels, metadata.width, metadata.height)
                }
                received(data, format, metadata) { DispatchQueue.main.async { self.capturing = false } }
            } else { self.message = "RAWデータを取得できませんでした。"; self.capturing = false }
        }
    }
}

final class RawPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint, Bool) -> Void)?
    private let focusRing = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.6; addGestureRecognizer(hold)
        focusRing.strokeColor = UIColor.systemYellow.cgColor; focusRing.fillColor = UIColor.clear.cgColor
        focusRing.lineWidth = 1; focusRing.opacity = 0; layer.addSublayer(focusRing)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        showFocus(gesture.location(in: self), locked: false)
    }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { showFocus(gesture.location(in: self), locked: true) }
    }
    private func showFocus(_ point: CGPoint, locked: Bool) {
        onFocus?(preview.captureDevicePointConverted(fromLayerPoint: point), locked)
        focusRing.removeAllAnimations()
        focusRing.path = UIBezierPath(rect: CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60)).cgPath
        focusRing.opacity = 1
        if !locked {
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0
            fade.beginTime = CACurrentMediaTime() + 0.8; fade.duration = 0.3; fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
            focusRing.add(fade, forKey: "fade")
        }
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
        view.onFocus = { camera.focus($0, locked: $1) }
        return view
    }
    func updateUIView(_ view: RawPreviewUIView, context: Context) {}
}
