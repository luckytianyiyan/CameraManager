//
//  CameraManager.swift
//  camera
//
//  Created by Natalia Terlecka on 10/10/14.
//  Copyright (c) 2014 imaginaryCloud. All rights reserved.
//

import AVFoundation
import Photos

public enum CameraOutputMode {
    case stillImage, videoWithMic, videoOnly
}

open class CameraManager: BaseCameraManager {
    private var library: PHPhotoLibrary?
    private var stillImageOutput: AVCaptureStillImageOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    lazy var mic: AVCaptureDevice? = {
        return AVCaptureDevice.default(for: AVMediaType.audio)
    }()
    fileprivate var locationManager: CameraLocationManager?
    /// Property to enable or disable location services. Location services in camera is used for EXIF data. Default is false
    open var shouldUseLocationServices: Bool = false {
        didSet {
            if shouldUseLocationServices == true {
                self.locationManager = CameraLocationManager()
            }
        }
    }
    
    private var tempFilePath: URL {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempMovie\(Date().timeIntervalSince1970)").appendingPathExtension("mp4")
        return tempURL
    }
    
    private var videoCompletion: ((_ videoURL: URL?, _ error: NSError?) -> Void)?
    
    override var connection: AVCaptureConnection? {
        switch cameraOutputMode {
        case .stillImage:
            return stillImageOutput?.connection(with: AVMediaType.video)
        case .videoOnly, .videoWithMic:
            return _getMovieOutput().connection(with: AVMediaType.video)
        }
    }
    
    /// Property to check video recording duration when in progress
    open var recordedDuration : CMTime { return movieOutput?.recordedDuration ?? kCMTimeZero }
    
    /// Property to check video recording file size when in progress
    open var recordedFileSize : Int64 { return movieOutput?.recordedFileSize ?? 0 }
    
    /// Property to change camera output.
    open var cameraOutputMode = CameraOutputMode.stillImage {
        didSet {
            guard cameraIsSetup else {
                return
            }
            if cameraOutputMode != oldValue {
                replaceOutputMode(cameraOutputMode, oldCameraOutputMode: oldValue)
            }
            setupMaxZoomScale()
            zoom(0)
        }
    }
    
    override func setupOutputs() {
        super.setupOutputs()
        if (stillImageOutput == nil) {
            stillImageOutput = AVCaptureStillImageOutput()
        }
        if (movieOutput == nil) {
            movieOutput = AVCaptureMovieFileOutput()
            movieOutput?.movieFragmentInterval = kCMTimeInvalid
        }
        if library == nil {
            library = PHPhotoLibrary.shared()
        }
    }
    
    override func setupOutputMode() {
        captureSession?.beginConfiguration()
        
        // configure new devices
        switch cameraOutputMode {
        case .stillImage:
            if (stillImageOutput == nil) {
                setupOutputs()
            }
            if let validStillImageOutput = stillImageOutput {
                if let captureSession = captureSession {
                    if captureSession.canAddOutput(validStillImageOutput) {
                        captureSession.addOutput(validStillImageOutput)
                    }
                }
            }
        case .videoOnly, .videoWithMic:
            let videoMovieOutput = _getMovieOutput()
            if let captureSession = captureSession {
                if captureSession.canAddOutput(videoMovieOutput) {
                    captureSession.addOutput(videoMovieOutput)
                }
            }
            
            if cameraOutputMode == .videoWithMic {
                if let validMic = _deviceInputFromDevice(mic) {
                    captureSession?.addInput(validMic)
                }
            }
        }
        captureSession?.commitConfiguration()
        super.setupOutputMode()
    }
    
    override func preset(for quality: CameraOutputQuality) -> AVCaptureSession.Preset {
        if quality == .high {
            return cameraOutputMode == .stillImage ? .photo : .high
        }
        return super.preset(for: quality)
    }
    
    func replaceOutputMode(_ newCameraOutputMode: CameraOutputMode, oldCameraOutputMode: CameraOutputMode?) {
        captureSession?.beginConfiguration()
        
        if let cameraOutputToRemove = oldCameraOutputMode {
            // remove current setting
            switch cameraOutputToRemove {
            case .stillImage:
                if let validStillImageOutput = stillImageOutput {
                    captureSession?.removeOutput(validStillImageOutput)
                }
            case .videoOnly, .videoWithMic:
                if let validMovieOutput = movieOutput {
                    captureSession?.removeOutput(validMovieOutput)
                }
                if cameraOutputToRemove == .videoWithMic {
                    removeMicInput()
                }
            }
        }
        
        // configure new devices
        switch newCameraOutputMode {
        case .stillImage:
            if (stillImageOutput == nil) {
                setupOutputs()
            }
            if let validStillImageOutput = stillImageOutput {
                if let captureSession = captureSession {
                    if captureSession.canAddOutput(validStillImageOutput) {
                        captureSession.addOutput(validStillImageOutput)
                    }
                }
            }
        case .videoOnly, .videoWithMic:
            let videoMovieOutput = _getMovieOutput()
            if let captureSession = captureSession {
                if captureSession.canAddOutput(videoMovieOutput) {
                    captureSession.addOutput(videoMovieOutput)
                }
            }
            
            if newCameraOutputMode == .videoWithMic {
                if let validMic = _deviceInputFromDevice(mic) {
                    captureSession?.addInput(validMic)
                }
            }
        }
        captureSession?.commitConfiguration()
        setupOutputMode()
    }
    
    override func cleanAllDatas() {
        super.cleanAllDatas()
        stillImageOutput = nil
        movieOutput = nil
        mic = nil
    }
    
    open override func askUserForCameraPermission(_ completion: @escaping (Bool) -> Void) {
        super.askUserForCameraPermission { allowedAccess in
            if allowedAccess == false {
                completion(false)
                return
            }
            
            AVCaptureDevice.requestAccess(for: AVMediaType.audio, completionHandler: { (allowedAccessAudio) -> Void in
                DispatchQueue.main.async(execute: { () -> Void in
                    completion(allowedAccessAudio)
                })
            })
        }
    }
    
    fileprivate func _performShutterAnimation(_ completion: (() -> Void)?) {
        
        if let validPreviewLayer = previewLayer {
            
            DispatchQueue.main.async {
                
                let duration = 0.1
                
                CATransaction.begin()
                
                if let completion = completion {
                    
                    CATransaction.setCompletionBlock(completion)
                }
                
                let fadeOutAnimation = CABasicAnimation(keyPath: "opacity")
                fadeOutAnimation.fromValue = 1.0
                fadeOutAnimation.toValue = 0.0
                validPreviewLayer.add(fadeOutAnimation, forKey: "opacity")
                
                let fadeInAnimation = CABasicAnimation(keyPath: "opacity")
                fadeInAnimation.fromValue = 0.0
                fadeInAnimation.toValue = 1.0
                fadeInAnimation.beginTime = CACurrentMediaTime() + duration * 2.0
                validPreviewLayer.add(fadeInAnimation, forKey: "opacity")
                
                CATransaction.commit()
            }
        }
    }
    
    fileprivate func _getStillImageOutput() -> AVCaptureStillImageOutput {
        if let stillImageOutput = stillImageOutput, let connection = stillImageOutput.connection(with: AVMediaType.video),
            connection.isActive {
            return stillImageOutput
        }
        let newStillImageOutput = AVCaptureStillImageOutput()
        stillImageOutput = newStillImageOutput
        if let captureSession = captureSession {
            if captureSession.canAddOutput(newStillImageOutput) {
                captureSession.beginConfiguration()
                captureSession.addOutput(newStillImageOutput)
                captureSession.commitConfiguration()
            }
        }
        return newStillImageOutput
    }
    
    fileprivate func _executeVideoCompletionWithURL(_ url: URL?, error: NSError?) {
        videoCompletion?(url, error)
        videoCompletion = nil
    }
    
    // MARK: Image
    
    /**
     Captures still image from currently running capture session.
     
     :param: imageCompletion Completion block containing the captured UIImage
     */
    open func capturePictureWithCompletion(_ imageCompletion: @escaping (UIImage?, NSError?) -> Void) {
        self.capturePictureDataWithCompletion { data, error in
            
            guard error == nil, let imageData = data else {
                imageCompletion(nil, error)
                return
            }
            
            if self.animateShutter {
                self._performShutterAnimation() {
                    self._capturePicture(imageData, imageCompletion)
                }
            } else {
                self._capturePicture(imageData, imageCompletion)
            }
        }
    }
    
    fileprivate func _capturePicture(_ imageData: Data, _ imageCompletion: (UIImage?, NSError?) -> Void) {
        guard let tempImage = UIImage(data: imageData) else {
            imageCompletion(nil, NSError())
            return
        }
        
        let image: UIImage
        if self.shouldFlipFrontCameraImage == true, self.cameraDevice == .front {
            guard let cgImage = tempImage.cgImage else {
                imageCompletion(nil, NSError())
                return
            }
            let flippedImage = UIImage(cgImage: cgImage, scale: tempImage.scale, orientation: .leftMirrored)
            image = flippedImage
        } else {
            image = tempImage
        }
        
        if self.writeFilesToPhoneLibrary == true, let library = self.library  {
            library.performChanges({
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                request.creationDate = Date()
                
                if let location = self.locationManager?.latestLocation {
                    request.location = location
                }
            }, completionHandler: { success, error in
                if let error = error {
                    DispatchQueue.main.async(execute: {
                        self._show(NSLocalizedString("Error", comment:""), message: error.localizedDescription)
                    })
                }
            })
        }
        
        imageCompletion(image, nil)
    }
    
    /**
     Captures still image from currently running capture session.
     
     :param: imageCompletion Completion block containing the captured imageData
     */
    open func capturePictureDataWithCompletion(_ imageCompletion: @escaping (Data?, NSError?) -> Void) {
        
        guard cameraIsSetup else {
            _show(NSLocalizedString("No capture session setup", comment:""), message: NSLocalizedString("I can't take any picture", comment:""))
            return
        }
        
        guard cameraOutputMode == .stillImage else {
            _show(NSLocalizedString("Capture session output mode video", comment:""), message: NSLocalizedString("I can't take any picture", comment:""))
            return
        }
        
        sessionQueue.async(execute: {
            let stillImageOutput = self._getStillImageOutput()
            stillImageOutput.captureStillImageAsynchronously(from: stillImageOutput.connection(with: AVMediaType.video)!, completionHandler: { [weak self] sample, error in
                
                if let error = error {
                    DispatchQueue.main.async(execute: {
                        self?._show(NSLocalizedString("Error", comment:""), message: error.localizedDescription)
                    })
                    imageCompletion(nil, error as NSError?)
                    return
                }
                
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sample!)
                imageCompletion(imageData, nil)
                
            })
        })
        
    }
    
    // MARK: Video
    
    fileprivate func _getMovieOutput() -> AVCaptureMovieFileOutput {
        if let movieOutput = movieOutput, let connection = movieOutput.connection(with: AVMediaType.video),
            connection.isActive {
            return movieOutput
        }
        let newMoviewOutput = AVCaptureMovieFileOutput()
        newMoviewOutput.movieFragmentInterval = kCMTimeInvalid
        movieOutput = newMoviewOutput
        if let captureSession = captureSession {
            if captureSession.canAddOutput(newMoviewOutput) {
                captureSession.beginConfiguration()
                captureSession.addOutput(newMoviewOutput)
                captureSession.commitConfiguration()
            }
        }
        return newMoviewOutput
    }
    
    /**
     Starts recording a video with or without voice as in the session preset.
     */
    open func startRecordingVideo() {
        if cameraOutputMode != .stillImage {
            _getMovieOutput().startRecording(to: tempFilePath, recordingDelegate: self)
        } else {
            _show(NSLocalizedString("Capture session output still image", comment:""), message: NSLocalizedString("I can only take pictures", comment:""))
        }
    }
    
    /**
     Stop recording a video. Save it to the cameraRoll and give back the url.
     */
    open func stopVideoRecording(_ completion:((_ videoURL: URL?, _ error: NSError?) -> Void)?) {
        if let runningMovieOutput = movieOutput {
            if runningMovieOutput.isRecording {
                videoCompletion = completion
                runningMovieOutput.stopRecording()
            }
        }
    }
    
    // MARK: Audio
    
    private func removeMicInput() {
        guard let inputs = captureSession?.inputs else { return }
        
        for input in inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                if deviceInput.device == mic {
                    captureSession?.removeInput(deviceInput)
                    break;
                }
            }
        }
    }
    
    // MARK: - Preview Layer
    
    open override func addPreviewLayerToView(_ view: UIView, completion: (() -> Void)? = nil) -> CameraState {
        return super.addPreviewLayerToView(view, completion: completion)
    }
    
    open func addPreviewLayerToView(_ view: UIView, newCameraOutputMode: CameraOutputMode, completion: (() -> Void)? = nil) -> CameraState {
        return addPreviewLayerToView(view, completion: { [weak self] in
            self?.cameraOutputMode = newCameraOutputMode
        })
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    fileprivate func saveVideoToLibrary(_ fileURL: URL) {
        if let validLibrary = library {
            validLibrary.performChanges({
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                request?.creationDate = Date()
                
                if let location = self.locationManager?.latestLocation {
                    request?.location = location
                }
            }, completionHandler: { success, error in
                if let error = error {
                    self._show(NSLocalizedString("Unable to save video to the iPhone.", comment:""), message: error.localizedDescription)
                    self._executeVideoCompletionWithURL(nil, error: error as NSError?)
                } else {
                    self._executeVideoCompletionWithURL(fileURL, error: error as NSError?)
                }
            })
        }
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    public func fileOutput(captureOutput: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        captureSession?.beginConfiguration()
        if flashMode != .off {
            updateFlashMode(flashMode)
        }
        captureSession?.commitConfiguration()
    }
    
    open func fileOutput(_ captureOutput: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        updateFlashMode(.off)
        if let error = error {
            _show(NSLocalizedString("Unable to save video to the iPhone", comment:""), message: error.localizedDescription)
        }
        else {
            if writeFilesToPhoneLibrary {
                if PHPhotoLibrary.authorizationStatus() == .authorized {
                    saveVideoToLibrary(outputFileURL)
                }
                else {
                    PHPhotoLibrary.requestAuthorization({ (autorizationStatus) in
                        if autorizationStatus == .authorized {
                            self.saveVideoToLibrary(outputFileURL)
                        }
                    })
                }
                
            } else {
                _executeVideoCompletionWithURL(outputFileURL, error: error as NSError?)
            }
        }
    }
}
