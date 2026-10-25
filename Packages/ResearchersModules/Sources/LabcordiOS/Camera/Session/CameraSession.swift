//
//  CameraSession.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import AVFoundation
import Dispatch
import Foundation

public actor CameraSession {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchSerialQueue(
        label: "com.researchers.camera.capture"
    )
    
    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }
    
    public init() {}
    
    private var isConfigured = false
    private var activeCamera: AVCaptureDevice?
    private var cachedPreviewConnector: CameraPreviewConnector?
    
    public func configureCamera() throws {
        guard !isConfigured else { return }
        
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraSessionError.permissionDenied
        }
        
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw CameraSessionError.cameraUnavaliable
        }
        
        let input = try AVCaptureDeviceInput(device: camera)
        
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        guard session.canAddInput(input) else {
            throw CameraSessionError.cannotAddInput
        }
        
        session.addInput(input)
        activeCamera = camera
        isConfigured = true
    }
    
    public func start() throws {
        try configureCamera()
        
        if !session.isRunning {
            session.startRunning()
        }
    }
    
    public func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    public func previewConnector() -> CameraPreviewConnector {
        if let cachedPreviewConnector {
            return cachedPreviewConnector
        }

        let connector = CameraPreviewConnector(session: session, device: activeCamera)
        cachedPreviewConnector = connector
        return connector
    }
}

public enum CameraSessionError: Error {
    case permissionDenied
    case cameraUnavaliable
    case cannotAddInput
}
