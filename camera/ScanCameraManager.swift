//
//  ScanCameraManager.swift
//  CameraManager
//
//  Created by luckytianyiyan on 2017/10/28.
//

import AVFoundation

public enum CameraTorchMode: Int {
    case off, on, auto
}

open class ScanCameraManager: BaseCameraManager {
    
    private var metadataOutput: AVCaptureMetadataOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    public var metadataCompletion: ((_ metadataObjects: [AVMetadataObject]) -> Void)?
    public var brightnessChange: ((_ value: CGFloat) -> Void)?
    private(set) var metadataObjectTypes: [AVMetadataObject.ObjectType]
    
    /// The Bool property to determine if current device has flash.
    open var hasTorch: Bool = {
        let hasTorchDevices = AVCaptureDevice.videoDevices.filter { $0.hasTorch }
        return !hasTorchDevices.isEmpty
    }()
    
    /// Property to change camera flash mode.
    open var torchMode = CameraTorchMode.off {
        didSet {
            guard cameraIsSetup, torchMode != oldValue else {
                return
            }
            updateTorchMode(torchMode)
            print("Torch Mode: \(torchMode.rawValue)")
        }
    }
    
    override var connection: AVCaptureConnection? {
        return metadataOutput?.connection(with: .metadata)
    }
    
    public init(metadataObjectTypes: [AVMetadataObject.ObjectType] = [.qr, .ean13, .ean8, .code128]) {
        self.metadataObjectTypes = metadataObjectTypes
        super.init()
    }
    
    override func setupOutputs() {
        super.setupOutputs()
        if metadataOutput == nil {
            metadataOutput = AVCaptureMetadataOutput()
            metadataOutput!.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        }
        if videoDataOutput == nil {
            videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput?.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        }
    }
    
    override func setupOutputMode() {
        captureSession?.beginConfiguration()
        if let session = captureSession {
            if let output = metadataOutput, session.canAddOutput(output) {
                session.addOutput(output)
                let availableMetadataObjectTypes = metadataOutput!.availableMetadataObjectTypes
                let types: [AVMetadataObject.ObjectType] = metadataObjectTypes.filter { availableMetadataObjectTypes.contains($0) }
                metadataOutput?.metadataObjectTypes = types
            }
            if let dataOutput = videoDataOutput, session.canAddOutput(dataOutput) {
                session.addOutput(dataOutput)
            }
        }
        
        captureSession?.commitConfiguration()
        super.setupOutputMode()
    }
    
    override func cleanAllDatas() {
        super.cleanAllDatas()
        metadataOutput = nil
        videoDataOutput = nil
    }
    
    func updateTorchMode(_ torchMode: CameraTorchMode) {
        captureSession?.beginConfiguration()
        defer { captureSession?.commitConfiguration() }
        for captureDevice in AVCaptureDevice.videoDevices  {
            guard let avTorchMode = AVCaptureDevice.TorchMode(rawValue: torchMode.rawValue) else {
                continue
            }
            if captureDevice.isTorchModeSupported(avTorchMode) {
                do {
                    try captureDevice.lockForConfiguration()
                } catch {
                    return
                }
                captureDevice.torchMode = avTorchMode
                captureDevice.unlockForConfiguration()
            }
        }
        
    }
}

extension ScanCameraManager: AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        metadataCompletion?(metadataObjects)
    }
}

extension ScanCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let dict = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) else {
            return
        }
        let metadata = NSDictionary(dictionary: dict)
        
        if let exifMetadata = metadata.object(forKey: kCGImagePropertyExifDictionary) as? [String: Any], let brightnessValue = exifMetadata[kCGImagePropertyExifBrightnessValue as String] as? CGFloat {
            brightnessChange?(brightnessValue)
        }
    }
}
