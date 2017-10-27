//
//  BaseCameraManager.swift
//  CameraManager
//
//  Created by luckytianyiyan on 2017/10/27.
//

import UIKit
import AVFoundation
import ImageIO
import MobileCoreServices

public enum CameraState {
    case ready, accessDenied, noDeviceFound, notDetermined
}

public enum CameraDevice {
    case front, back
}

public enum CameraFlashMode: Int {
    case off, on, auto
}

public enum CameraOutputQuality: Int {
    case low, medium, high
}

/// Class for handling iDevices custom camera usage
open class BaseCameraManager: NSObject {
    
    // MARK: - Public properties
    
    /// Capture session to customize camera settings.
    open var captureSession: AVCaptureSession?
    
    /// Property to determine if the manager should show the error for the user. If you want to show the errors yourself set this to false. If you want to add custom error UI set showErrorBlock property. Default value is false.
    open var showErrorsToUsers = false
    
    /// Property to determine if the manager should show the camera permission popup immediatly when it's needed or you want to show it manually. Default value is true. Be carful cause using the camera requires permission, if you set this value to false and don't ask manually you won't be able to use the camera.
    open var showAccessPermissionPopupAutomatically = true
    
    /// A block creating UI to present error message to the user. This can be customised to be presented on the Window root view controller, or to pass in the viewController which will present the UIAlertController, for example.
    open var showErrorBlock:(_ erTitle: String, _ erMessage: String) -> Void = { (erTitle: String, erMessage: String) -> Void in
        
        //        var alertController = UIAlertController(title: erTitle, message: erMessage, preferredStyle: .Alert)
        //        alertController.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: { (alertAction) -> Void in  }))
        //
        //        if let topController = UIApplication.sharedApplication().keyWindow?.rootViewController {
        //            topController.presentViewController(alertController, animated: true, completion:nil)
        //        }
    }
    
    /// Property to determine if manager should write the resources to the phone library. Default value is true.
    open var writeFilesToPhoneLibrary = true
    
    /// Property to determine if manager should follow device orientation. Default value is true.
    open var shouldRespondToOrientationChanges = true {
        didSet {
            if shouldRespondToOrientationChanges {
                _startFollowingDeviceOrientation()
            } else {
                _stopFollowingDeviceOrientation()
            }
        }
    }
    
    /// Property to determine if manager should horizontally flip image took by front camera. Default value is false.
    open var shouldFlipFrontCameraImage = false
    
    open var shouldKeepViewAtOrientationChanges = false
    
    /// The Bool property to determine if the camera is ready to use.
    open var cameraIsReady: Bool {
        get {
            return cameraIsSetup
        }
    }
    
    /// The Bool property to determine if current device has front camera.
    open var hasFrontCamera: Bool = {
        let frontDevices = AVCaptureDevice.videoDevices.filter { $0.position == .front }
        return !frontDevices.isEmpty
    }()
    
    /// The Bool property to determine if current device has flash.
    open var hasFlash: Bool = {
        let hasFlashDevices = AVCaptureDevice.videoDevices.filter { $0.hasFlash }
        return !hasFlashDevices.isEmpty
    }()
    
    /// Property to enable or disable flip animation when switch between back and front camera. Default value is true.
    open var animateCameraDeviceChange: Bool = true
    
    /// Property to enable or disable shutter animation when taking a picture. Default value is true.
    open var animateShutter: Bool = true
    
    /// Property to change camera device between front and back.
    open var cameraDevice = CameraDevice.back {
        didSet {
            guard cameraIsSetup, cameraDevice != oldValue else {
                return
            }
            if animateCameraDeviceChange {
                _doFlipAnimation()
            }
            _updateCameraDevice(cameraDevice)
            updateFlashMode(flashMode)
            setupMaxZoomScale()
            zoom(0)
        }
    }
    
    /// Property to change camera flash mode.
    open var flashMode = CameraFlashMode.off {
        didSet {
            guard cameraIsSetup, flashMode != oldValue else {
                return
            }
            updateFlashMode(flashMode)
            print("Flash Mode: \(flashMode.rawValue)")
        }
    }
    
    /// Property to change camera output quality.
    open var cameraOutputQuality = CameraOutputQuality.high {
        didSet {
            guard cameraIsSetup, cameraOutputQuality != oldValue else {
                return
            }
            _updateCameraQualityMode(cameraOutputQuality)
        }
    }
    
    //Properties to set focus and capture mode when tap to focus is used (_focusStart)
    open var focusMode : AVCaptureDevice.FocusMode = .continuousAutoFocus
    open var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
    
    public lazy var gestureController: CameraGestureController = {
        return CameraGestureController(manager: self)
    }()
    
    // MARK: - Private properties
    
    fileprivate weak var embeddingView: UIView?
    
    var sessionQueue: DispatchQueue = DispatchQueue(label: "CameraSessionQueue", attributes: [])
    
    lazy var frontCameraDevice: AVCaptureDevice? = {
        return AVCaptureDevice.videoDevices.filter { $0.position == .front }.first
    }()
    
    lazy var backCameraDevice: AVCaptureDevice? = {
        return AVCaptureDevice.videoDevices.filter { $0.position == .back }.first
    }()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var cameraIsSetup = false
    fileprivate var cameraIsObservingDeviceOrientation = false
    
    var zoomScale: CGFloat = 1.0
    var beginZoomScale: CGFloat = 1.0
    fileprivate var maxZoomScale: CGFloat = 1.0
    
    // MARK: - CameraManager
    
    /**
     Inits a capture session and adds a preview layer to the given view. Preview layer bounds will automaticaly be set to match given view. Default session is initialized with still image output.
     
     :param: view The view you want to add the preview layer to
     :param: cameraOutputMode The mode you want capturesession to run image / video / video and microphone
     :param: completion Optional completion block
     
     :returns: Current state of the camera: Ready / AccessDenied / NoDeviceFound / NotDetermined.
     */
    open func addPreviewLayerToView(_ view: UIView, completion: (() -> Void)? = nil) -> CameraState {
        if _canLoadCamera() {
            if embeddingView != nil {
                previewLayer?.removeFromSuperlayer()
            }
            if cameraIsSetup {
                _addPreviewLayerToView(view)
                completion?()
            } else {
                _setupCamera {
                    self._addPreviewLayerToView(view)
                    completion?()
                }
            }
        }
        return _checkIfCameraIsAvailable()
    }
    
    /**
     Asks the user for camera permissions. Only works if the permissions are not yet determined. Note that it'll also automaticaly ask about the microphone permissions if you selected VideoWithMic output.
     
     :param: completion Completion block with the result of permission request
     */
    open func askUserForCameraPermission(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (allowedAccess) -> Void in
            DispatchQueue.main.async(execute: { () -> Void in
                completion(allowedAccess)
            })
        })
    }
    
    /**
     Stops running capture session but all setup devices, inputs and outputs stay for further reuse.
     */
    open func stopCaptureSession() {
        captureSession?.stopRunning()
        _stopFollowingDeviceOrientation()
    }
    
    /**
     Resumes capture session.
     */
    open func resumeCaptureSession() {
        if let validCaptureSession = captureSession {
            if !validCaptureSession.isRunning && cameraIsSetup {
                validCaptureSession.startRunning()
                _startFollowingDeviceOrientation()
            }
        } else {
            if _canLoadCamera() {
                if cameraIsSetup {
                    stopAndRemoveCaptureSession()
                }
                _setupCamera {
                    if let validEmbeddingView = self.embeddingView {
                        self._addPreviewLayerToView(validEmbeddingView)
                    }
                    self._startFollowingDeviceOrientation()
                }
            }
        }
    }
    
    /**
     Stops running capture session and removes all setup devices, inputs and outputs.
     */
    open func stopAndRemoveCaptureSession() {
        stopCaptureSession()
        let oldAnimationValue = animateCameraDeviceChange
        cleanAllDatas()
        animateCameraDeviceChange = oldAnimationValue
    }
    
    func cleanAllDatas() {
        animateCameraDeviceChange = false
        cameraDevice = .back
        cameraIsSetup = false
        previewLayer = nil
        captureSession = nil
        frontCameraDevice = nil
        backCameraDevice = nil
    }
    
    /**
     Current camera status.
     
     :returns: Current state of the camera: Ready / AccessDenied / NoDeviceFound / NotDetermined
     */
    open func currentCameraStatus() -> CameraState {
        return _checkIfCameraIsAvailable()
    }
    
    /**
     Change current flash mode to next value from available ones.
     
     :returns: Current flash mode: Off / On / Auto
     */
    open func changeFlashMode() -> CameraFlashMode {
        guard let newFlashMode = CameraFlashMode(rawValue: (flashMode.rawValue+1)%3) else { return flashMode }
        flashMode = newFlashMode
        return flashMode
    }
    
    /**
     Change current output quality mode to next value from available ones.
     
     :returns: Current quality mode: Low / Medium / High
     */
    open func changeQualityMode() -> CameraOutputQuality {
        guard let newQuality = CameraOutputQuality(rawValue: (cameraOutputQuality.rawValue+1)%3) else { return cameraOutputQuality }
        cameraOutputQuality = newQuality
        return cameraOutputQuality
    }
    
    // MARK: - CameraManager()
    
    var connection: AVCaptureConnection? {
        return nil
    }
    
    @objc func _orientationChanged() {
        let currentConnection: AVCaptureConnection? = connection
        
        guard let validPreviewLayer = previewLayer else {
            return
        }
        if !shouldKeepViewAtOrientationChanges {
            if let validPreviewLayerConnection = validPreviewLayer.connection, validPreviewLayerConnection.isVideoOrientationSupported {
                validPreviewLayerConnection.videoOrientation = _currentVideoOrientation()
            }
        }
        if let validOutputLayerConnection = currentConnection,
            validOutputLayerConnection.isVideoOrientationSupported {
            validOutputLayerConnection.videoOrientation = _currentVideoOrientation()
        }
        if !shouldKeepViewAtOrientationChanges {
            DispatchQueue.main.async(execute: { () -> Void in
                if let validEmbeddingView = self.embeddingView {
                    validPreviewLayer.frame = validEmbeddingView.bounds
                }
            })
        }
    }
    
    fileprivate func _currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }
    
    fileprivate func _canLoadCamera() -> Bool {
        let currentCameraState = _checkIfCameraIsAvailable()
        return currentCameraState == .ready || (currentCameraState == .notDetermined && showAccessPermissionPopupAutomatically)
    }
    
    fileprivate func _setupCamera(_ completion: @escaping () -> Void) {
        captureSession = AVCaptureSession()
        
        sessionQueue.async(execute: {
            if let validCaptureSession = self.captureSession {
                validCaptureSession.beginConfiguration()
                validCaptureSession.sessionPreset = AVCaptureSession.Preset.high
                self._updateCameraDevice(self.cameraDevice)
                self.setupOutputs()
                self.setupOutputMode()
                self._setupPreviewLayer()
                validCaptureSession.commitConfiguration()
                self.updateFlashMode(self.flashMode)
                self._updateCameraQualityMode(self.cameraOutputQuality)
                validCaptureSession.startRunning()
                self._startFollowingDeviceOrientation()
                self.cameraIsSetup = true
                self._orientationChanged()
                
                completion()
            }
        })
    }
    
    fileprivate func _startFollowingDeviceOrientation() {
        if shouldRespondToOrientationChanges && !cameraIsObservingDeviceOrientation {
            NotificationCenter.default.addObserver(self, selector: #selector(CameraManager._orientationChanged), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
            cameraIsObservingDeviceOrientation = true
        }
    }
    
    fileprivate func _stopFollowingDeviceOrientation() {
        guard cameraIsObservingDeviceOrientation else {
            return
        }
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
        cameraIsObservingDeviceOrientation = false
    }
    
    fileprivate func _addPreviewLayerToView(_ view: UIView) {
        embeddingView = view
        DispatchQueue.main.async(execute: { () -> Void in
            guard let previewLayer = self.previewLayer else { return }
            previewLayer.frame = view.layer.bounds
            view.clipsToBounds = true
            view.layer.addSublayer(previewLayer)
        })
    }
    
    func setupMaxZoomScale() {
        var maxZoom: CGFloat = 1.0
        beginZoomScale = 1.0
        
        if cameraDevice == .back, let backCameraDevice = backCameraDevice  {
            maxZoom = backCameraDevice.activeFormat.videoMaxZoomFactor
        } else if cameraDevice == .front, let frontCameraDevice = frontCameraDevice {
            maxZoom = frontCameraDevice.activeFormat.videoMaxZoomFactor
        }
        
        maxZoomScale = maxZoom
    }
    
    fileprivate func _checkIfCameraIsAvailable() -> CameraState {
        let deviceHasCamera = UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.rear) || UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.front)
        if deviceHasCamera {
            let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
            let userAgreedToUseIt = authorizationStatus == .authorized
            if userAgreedToUseIt {
                return .ready
            } else if authorizationStatus == AVAuthorizationStatus.notDetermined {
                return .notDetermined
            } else {
                _show(NSLocalizedString("Camera access denied", comment:""), message:NSLocalizedString("You need to go to settings app and grant acces to the camera device to use it.", comment:""))
                return .accessDenied
            }
        } else {
            _show(NSLocalizedString("Camera unavailable", comment:""), message:NSLocalizedString("The device does not have a camera.", comment:""))
            return .noDeviceFound
        }
    }
    
    func setupOutputMode() {
    }
    
    func setupOutputs() {
        
    }
    
    fileprivate func _setupPreviewLayer() {
        if let validCaptureSession = captureSession {
            previewLayer = AVCaptureVideoPreviewLayer(session: validCaptureSession)
            previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        }
    }
    
    /**
     Switches between the current and specified camera using a flip animation similar to the one used in the iOS stock camera app
     */
    
    fileprivate var cameraTransitionView: UIView?
    fileprivate var transitionAnimating = false
    
    open func _doFlipAnimation() {
        
        if transitionAnimating {
            return
        }
        
        if let validEmbeddingView = embeddingView {
            if let validPreviewLayer = previewLayer {
                
                var tempView = UIView()
                
                if CameraManager._blurSupported() {
                    
                    let blurEffect = UIBlurEffect(style: .light)
                    tempView = UIVisualEffectView(effect: blurEffect)
                    tempView.frame = validEmbeddingView.bounds
                }
                else {
                    
                    tempView = UIView(frame: validEmbeddingView.bounds)
                    tempView.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
                }
                
                validEmbeddingView.insertSubview(tempView, at: Int(validPreviewLayer.zPosition + 1))
                
                cameraTransitionView = validEmbeddingView.snapshotView(afterScreenUpdates: true)
                
                if let cameraTransitionView = cameraTransitionView {
                    validEmbeddingView.insertSubview(cameraTransitionView, at: Int(validEmbeddingView.layer.zPosition + 1))
                }
                tempView.removeFromSuperview()
                
                transitionAnimating = true
                
                validPreviewLayer.opacity = 0.0
                
                DispatchQueue.main.async() {
                    self._flipCameraTransitionView()
                }
            }
        }
    }
    
    // Determining whether the current device actually supports blurring
    // As seen on: http://stackoverflow.com/a/29997626/2269387
    fileprivate class func _blurSupported() -> Bool {
        var supported = Set<String>()
        supported.insert("iPad")
        supported.insert("iPad1,1")
        supported.insert("iPhone1,1")
        supported.insert("iPhone1,2")
        supported.insert("iPhone2,1")
        supported.insert("iPhone3,1")
        supported.insert("iPhone3,2")
        supported.insert("iPhone3,3")
        supported.insert("iPod1,1")
        supported.insert("iPod2,1")
        supported.insert("iPod2,2")
        supported.insert("iPod3,1")
        supported.insert("iPod4,1")
        supported.insert("iPad2,1")
        supported.insert("iPad2,2")
        supported.insert("iPad2,3")
        supported.insert("iPad2,4")
        supported.insert("iPad3,1")
        supported.insert("iPad3,2")
        supported.insert("iPad3,3")
        
        return !supported.contains(_hardwareString())
    }
    
    fileprivate class func _hardwareString() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let deviceName = String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)!.trimmingCharacters(in: .controlCharacters)
        return deviceName
    }
    
    fileprivate func _flipCameraTransitionView() {
        
        if let cameraTransitionView = cameraTransitionView {
            
            UIView.transition(with: cameraTransitionView,
                              duration: 0.5,
                              options: UIViewAnimationOptions.transitionFlipFromLeft,
                              animations: nil,
                              completion: { (finished) -> Void in
                                self._removeCameraTransistionView()
            })
        }
    }
    
    
    fileprivate func _removeCameraTransistionView() {
        
        if let cameraTransitionView = cameraTransitionView {
            if let validPreviewLayer = previewLayer {
                
                validPreviewLayer.opacity = 1.0
            }
            
            UIView.animate(withDuration: 0.5,
                           animations: { () -> Void in
                            
                            cameraTransitionView.alpha = 0.0
                            
            }, completion: { (finished) -> Void in
                
                self.transitionAnimating = false
                
                cameraTransitionView.removeFromSuperview()
                self.cameraTransitionView = nil
            })
        }
    }
    
    fileprivate func _updateCameraDevice(_ deviceType: CameraDevice) {
        if let validCaptureSession = captureSession {
            validCaptureSession.beginConfiguration()
            defer { validCaptureSession.commitConfiguration() }
            let inputs: [AVCaptureInput] = validCaptureSession.inputs
            
            for input in inputs {
                if let deviceInput = input as? AVCaptureDeviceInput {
                    validCaptureSession.removeInput(deviceInput)
                }
            }
            
            switch cameraDevice {
            case .front:
                if hasFrontCamera {
                    if let validFrontDevice = _deviceInputFromDevice(frontCameraDevice) {
                        if !inputs.contains(validFrontDevice) {
                            validCaptureSession.addInput(validFrontDevice)
                        }
                    }
                }
            case .back:
                if let validBackDevice = _deviceInputFromDevice(backCameraDevice) {
                    if !inputs.contains(validBackDevice) {
                        validCaptureSession.addInput(validBackDevice)
                    }
                }
            }
        }
    }
    
    func updateFlashMode(_ flashMode: CameraFlashMode) {
        captureSession?.beginConfiguration()
        defer { captureSession?.commitConfiguration() }
        for captureDevice in AVCaptureDevice.videoDevices  {
            guard let avFlashMode = AVCaptureDevice.FlashMode(rawValue: flashMode.rawValue) else { continue }
            if (captureDevice.isFlashModeSupported(avFlashMode)) {
                do {
                    try captureDevice.lockForConfiguration()
                } catch {
                    return
                }
                captureDevice.flashMode = avFlashMode
                captureDevice.unlockForConfiguration()
            }
        }
        
    }
    
    func preset(for quality: CameraOutputQuality) -> AVCaptureSession.Preset {
        switch (quality) {
        case CameraOutputQuality.low:
            return AVCaptureSession.Preset.low
        case CameraOutputQuality.medium:
            return AVCaptureSession.Preset.medium
        case CameraOutputQuality.high:
            return AVCaptureSession.Preset.high
        }
    }
    
    func _updateCameraQualityMode(_ newCameraOutputQuality: CameraOutputQuality) {
        guard let validCaptureSession = captureSession else {
            _show(NSLocalizedString("Camera error", comment:""), message: NSLocalizedString("No valid capture session found, I can't take any pictures or videos.", comment:""))
            return
        }
        let sessionPreset = preset(for: newCameraOutputQuality)
        if validCaptureSession.canSetSessionPreset(sessionPreset) {
            validCaptureSession.beginConfiguration()
            validCaptureSession.sessionPreset = sessionPreset
            validCaptureSession.commitConfiguration()
        } else {
            _show(NSLocalizedString("Preset not supported", comment:""), message: NSLocalizedString("Camera preset not supported. Please try another one.", comment:""))
        }
    }
    
    func _show(_ title: String, message: String) {
        guard showErrorsToUsers else {
            return
        }
        DispatchQueue.main.async(execute: { () -> Void in
            self.showErrorBlock(title, message)
        })
    }
    
    func _deviceInputFromDevice(_ device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else {
            return nil
        }
        do {
            return try AVCaptureDeviceInput(device: validDevice)
        } catch let outError {
            _show(NSLocalizedString("Device setup error occured", comment:""), message: "\(outError)")
            return nil
        }
    }
    
    deinit {
        stopAndRemoveCaptureSession()
        _stopFollowingDeviceOrientation()
    }
}

extension BaseCameraManager: UIGestureRecognizerDelegate {
    // MARK: - Zoom
    
    @objc
    func _zoomStart(_ recognizer: UIPinchGestureRecognizer) {
        guard let view = embeddingView,
            let previewLayer = previewLayer
            else { return }
        
        var allTouchesOnPreviewLayer = true
        let numTouch = recognizer.numberOfTouches
        
        for i in 0 ..< numTouch {
            let location = recognizer.location(ofTouch: i, in: view)
            let convertedTouch = previewLayer.convert(location, from: previewLayer.superlayer)
            if !previewLayer.contains(convertedTouch) {
                allTouchesOnPreviewLayer = false
                break
            }
        }
        if allTouchesOnPreviewLayer {
            zoom(recognizer.scale)
        }
    }
    
    func zoom(_ scale: CGFloat) {
        let device: AVCaptureDevice?
        
        switch cameraDevice {
        case .back:
            device = backCameraDevice
        case .front:
            device = frontCameraDevice
        }
        
        do {
            let captureDevice = device
            try captureDevice?.lockForConfiguration()
            
            zoomScale = max(1.0, min(beginZoomScale * scale, maxZoomScale))
            
            captureDevice?.videoZoomFactor = zoomScale
            
            captureDevice?.unlockForConfiguration()
            
        } catch {
            print("Error locking configuration")
        }
    }
    
}

fileprivate extension AVCaptureDevice {
    fileprivate static var videoDevices: [AVCaptureDevice] {
        return AVCaptureDevice.devices(for: AVMediaType.video)
    }
}
