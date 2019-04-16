//
//  CameraGestureController.swift
//  CameraManager
//
//  Created by luckytianyiyan on 2017/9/19.
//

import Foundation
import AVFoundation

public protocol CameraGestureControllerDelegate: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
}

public class CameraGestureController: NSObject {
    private(set) lazy var zoomGesture = UIPinchGestureRecognizer()
    private(set) lazy var focusGesture = UITapGestureRecognizer()
    fileprivate weak var manager: BaseCameraManager?
    fileprivate var lastFocusRectangle: CAShapeLayer? = nil
    open var focusRectangleColor: UIColor = UIColor(red:1, green:0.83, blue:0, alpha:0.95)
    public weak var delegate: CameraGestureControllerDelegate?
    
    init(manager: BaseCameraManager) {
        super.init()
        self.manager = manager
    }
    
    public func attachZoom(_ view: UIView) {
        guard let manager = self.manager else {
            return
        }
        DispatchQueue.main.async {
            self.zoomGesture.addTarget(manager, action: #selector(manager._zoomStart(_:)))
            view.addGestureRecognizer(self.zoomGesture)
            self.zoomGesture.delegate = self
        }
    }
    
    public func attachFocus(_ view: UIView) {
        DispatchQueue.main.async {
            self.focusGesture.addTarget(self, action: #selector(self._focusStart(_:)))
            view.addGestureRecognizer(self.focusGesture)
            self.focusGesture.delegate = self
        }
    }
    
    // MARK: - Pan
    
    @objc func _focusStart(_ recognizer: UITapGestureRecognizer) {
        guard let manager = self.manager else {
            return
        }
        
        let device: AVCaptureDevice?
        
        switch manager.cameraDevice {
        case .back:
            device = manager.backCameraDevice
        case .front:
            device = manager.frontCameraDevice
        }
        
        if let validDevice = device {
            
            if let validPreviewLayer = manager.previewLayer,
                let view = recognizer.view
            {
                let pointInPreviewLayer = view.layer.convert(recognizer.location(in: view), to: validPreviewLayer)
                let pointOfInterest = validPreviewLayer.captureDevicePointConverted(fromLayerPoint: pointInPreviewLayer)
                
                do {
                    try validDevice.lockForConfiguration()
                    
                    _showFocusRectangle(at: pointInPreviewLayer, in: validPreviewLayer)
                    
                    if validDevice.isFocusPointOfInterestSupported {
                        validDevice.focusPointOfInterest = pointOfInterest;
                    }
                    
                    if  validDevice.isExposurePointOfInterestSupported {
                        validDevice.exposurePointOfInterest = pointOfInterest;
                    }
                    
                    if validDevice.isFocusModeSupported(manager.focusMode) {
                        validDevice.focusMode = manager.focusMode
                    }
                    
                    if validDevice.isExposureModeSupported(manager.exposureMode) {
                        validDevice.exposureMode = manager.exposureMode
                    }
                    
                    validDevice.unlockForConfiguration()
                }
                catch let error {
                    print(error)
                }
            }
        }
    }
    
    fileprivate func _showFocusRectangle(at focusPoint: CGPoint, in layer: CALayer) {
        if let lastFocusRectangle = lastFocusRectangle {
            
            lastFocusRectangle.removeFromSuperlayer()
            self.lastFocusRectangle = nil
        }
        
        let size = CGSize(width: 75, height: 75)
        let rect = CGRect(origin: CGPoint(x: focusPoint.x - size.width / 2.0, y: focusPoint.y - size.height / 2.0), size: size)
        
        let endPath = UIBezierPath(rect: rect)
        endPath.move(to: CGPoint(x: rect.minX + size.width / 2.0, y: rect.minY))
        endPath.addLine(to: CGPoint(x: rect.minX + size.width / 2.0, y: rect.minY + 5.0))
        endPath.move(to: CGPoint(x: rect.maxX, y: rect.minY + size.height / 2.0))
        endPath.addLine(to: CGPoint(x: rect.maxX - 5.0, y: rect.minY + size.height / 2.0))
        endPath.move(to: CGPoint(x: rect.minX + size.width / 2.0, y: rect.maxY))
        endPath.addLine(to: CGPoint(x: rect.minX + size.width / 2.0, y: rect.maxY - 5.0))
        endPath.move(to: CGPoint(x: rect.minX, y: rect.minY + size.height / 2.0))
        endPath.addLine(to: CGPoint(x: rect.minX + 5.0, y: rect.minY + size.height / 2.0))
        
        let startPath = UIBezierPath(cgPath: endPath.cgPath)
        let scaleAroundCenterTransform = CGAffineTransform(translationX: -focusPoint.x, y: -focusPoint.y).concatenating(CGAffineTransform(scaleX: 2.0, y: 2.0).concatenating(CGAffineTransform(translationX: focusPoint.x, y: focusPoint.y)))
        startPath.apply(scaleAroundCenterTransform)
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = endPath.cgPath
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = focusRectangleColor.cgColor
        shapeLayer.lineWidth = 1.0
        
        layer.addSublayer(shapeLayer)
        lastFocusRectangle = shapeLayer
        
        CATransaction.begin()
        
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut))
        
        CATransaction.setCompletionBlock() {
            if shapeLayer.superlayer != nil {
                shapeLayer.removeFromSuperlayer()
                self.lastFocusRectangle = nil
            }
        }
        
        let appearPathAnimation = CABasicAnimation(keyPath: "path")
        appearPathAnimation.fromValue = startPath.cgPath
        appearPathAnimation.toValue = endPath.cgPath
        shapeLayer.add(appearPathAnimation, forKey: "path")
        
        let appearOpacityAnimation = CABasicAnimation(keyPath: "opacity")
        appearOpacityAnimation.fromValue = 0.0
        appearOpacityAnimation.toValue = 1.0
        shapeLayer.add(appearOpacityAnimation, forKey: "opacity")
        
        let disappearOpacityAnimation = CABasicAnimation(keyPath: "opacity")
        disappearOpacityAnimation.fromValue = 1.0
        disappearOpacityAnimation.toValue = 0.0
        disappearOpacityAnimation.beginTime = CACurrentMediaTime() + 0.8
        disappearOpacityAnimation.fillMode = CAMediaTimingFillMode.forwards
        disappearOpacityAnimation.isRemovedOnCompletion = false
        shapeLayer.add(disappearOpacityAnimation, forKey: "opacity")
        
        CATransaction.commit()
    }
}

extension CameraGestureController: UIGestureRecognizerDelegate {
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let delegate = self.delegate, delegate.gestureRecognizerShouldBegin(gestureRecognizer) == false {
            return false
        }
        if let manager = self.manager, gestureRecognizer.isKind(of: UIPinchGestureRecognizer.self) {
            manager.beginZoomScale = manager.zoomScale
        }
        
        return true
    }
}
