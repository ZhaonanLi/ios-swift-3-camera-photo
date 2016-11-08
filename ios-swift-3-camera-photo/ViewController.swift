//
//  ViewController.swift
//  ios-swift-3-camera-photo
//
//  Created by Zhaonan Li on 11/7/16.
//  Copyright © 2016 Zhaonan Li. All rights reserved.
//

import UIKit
import GLKit
import Photos
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var takePhotoBtn: UIButton!
    @IBOutlet weak var savePhotoBtn: UIButton!
    @IBOutlet weak var uploadPhotoBtn: UIButton!
    
    var stillImageOutput: AVCaptureStillImageOutput?
    var capturedUIImage: UIImage?
    
    lazy var glContext: EAGLContext = {
        let glContext = EAGLContext(api: .openGLES2)
        return glContext!
    }()
    
    lazy var glView: GLKView = {
        let glView = GLKView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: self.cameraView.bounds.width,
                height: self.cameraView.bounds.height
            ),
            context: self.glContext
        )
        return glView
    }()
    
    lazy var ciContext: CIContext = {
        let ciContext = CIContext(eaglContext: self.glContext)
        return ciContext
    }()
    
    lazy var cameraSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = AVCaptureSessionPresetPhoto
        return session
    }()
    
    lazy var photoFullPath: String = {
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true)[0]
        
        let photoFullPath = documentsPath + "/swift_3_camera_capture_photo.png"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: photoFullPath) {
            do {
                try fileManager.removeItem(at: URL(string: photoFullPath)!)
            } catch let error as NSError {
                print (error)
            }
        }
        
        return photoFullPath
    }()
    

    // Disable auto rotation.
    override var shouldAutorotate: Bool {
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        setupCameraSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        cameraView.addSubview(glView)
        cameraSession.startRunning()
    }
    
    func setupCameraSession() {
        let captureDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        do {
            cameraSession.beginConfiguration()
            
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            if cameraSession.canAddInput(deviceInput) {
                cameraSession.addInput(deviceInput)
            }
            
            stillImageOutput = AVCaptureStillImageOutput()
            stillImageOutput!.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
            if cameraSession.canAddOutput(stillImageOutput) {
                cameraSession.addOutput(stillImageOutput)
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as AnyHashable: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if cameraSession.canAddOutput(videoOutput) {
                cameraSession.addOutput(videoOutput)
            }
            
            cameraSession.commitConfiguration()
            
            let videoStreamingQueue = DispatchQueue(label: "com.currentProject.videoStreamingQueue")
            videoOutput.setSampleBufferDelegate(self, queue: videoStreamingQueue)
        } catch let error as NSError {
            print (error)
        }
    }
    
    
    
    
    
    
    

    @IBAction func takePhoto(_ sender: Any) {
        if let videoConnection = stillImageOutput!.connection(withMediaType: AVMediaTypeVideo) {
            stillImageOutput!.captureStillImageAsynchronously(from: videoConnection, completionHandler: { (cmSampleBuffer, error) in
                
                if error != nil {
                    print (error!)
                    return
                }
                
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(cmSampleBuffer)
                let ciImage = CIImage(data: imageData!)
                
                // Apply filter on ciImage here//////////////////////////////////////////////////////////////
                var affineTransform = CGAffineTransform(
                    translationX: (ciImage?.extent.width)! / 2,
                    y: (ciImage?.extent.height)! / 2
                )
                affineTransform = affineTransform.rotated(by: CGFloat(-1 * M_PI_2))
                affineTransform = affineTransform.translatedBy(
                    x: -(ciImage?.extent.width)! / 2,
                    y: -(ciImage?.extent.height)! / 2
                )
                
                let transformFilter = CIFilter(
                    name: "CIAffineTransform",
                    withInputParameters: [
                        kCIInputImageKey: ciImage!,
                        kCIInputTransformKey: affineTransform
                    ]
                )
                
                let transformedCIImage = transformFilter!.outputImage!
                /////////////////////////////////////////////////////////////////////////////////////////////
                
                let cgImage = self.ciContext.createCGImage(transformedCIImage, from: transformedCIImage.extent)
                self.capturedUIImage = UIImage(cgImage: cgImage!, scale: 1.0, orientation: UIImageOrientation.up)
            })
        }
    }

    
    
    @IBAction func savePhoto(_ sender: Any) {
        if self.capturedUIImage == nil {
            print ("capturedUIImage is nil, there is no image to be saved")
            return
        }
        
        if PHPhotoLibrary.authorizationStatus() != PHAuthorizationStatus.authorized {
            print ("the photo auth status is not .authorized.")
            PHPhotoLibrary.requestAuthorization({ (PHAuthorizationStatus) in
                
                DispatchQueue.main.async {
                    print ("HERE is requesting the photo access.")
                }
                
                switch PHAuthorizationStatus {
                case .authorized:
                    DispatchQueue.main.async {
                        print ("The photo auth status is authorized.")
                    }
                    
                    do {
                        try UIImagePNGRepresentation(self.capturedUIImage!)!.write(
                            to: URL(fileURLWithPath: self.photoFullPath),
                            options: .atomic)
                    } catch let error as NSError {
                        print (error)
                    }
                    
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: URL(fileURLWithPath: self.photoFullPath))
                    }, completionHandler: { completed, error in
                        if error != nil {
                            print ("Cannot move the photo from the file to camera roll, error:\(error).")
                            return
                        }
                        
                        if completed {
                            print ("Succeed in moving the photo from the file to camera roll.")
                        }
                    })
                    
                case .denied:
                    DispatchQueue.main.async {
                        print ("The photo auth status is denied.")
                    }
                
                case .notDetermined:
                    DispatchQueue.main.async {
                        print ("The photo auth status is notDetermined.")
                    }
                
                default:
                    DispatchQueue.main.async {
                        print ("Here don't know the photo auth status.")
                    }
                }
            })
        }
    }
    
    
    
    @IBAction func uploadPhoto(_ sender: Any) {
    }
    
    
    
    
    
    
    
    
    
    
    
    
    // Implement the delegate method
    // Interface: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        // Here we can collect the frames, and process them.
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer!)
        
        // Rotate the ciImage 90 degrees to right.
        var affineTransform = CGAffineTransform(
            translationX: ciImage.extent.width / 2,
            y: ciImage.extent.height / 2
        )
        affineTransform = affineTransform.rotated(by: CGFloat(-1 * M_PI_2))
        affineTransform = affineTransform.translatedBy(
            x: -ciImage.extent.width / 2,
            y: -ciImage.extent.height / 2
        )
        
        let transformFilter = CIFilter(
            name: "CIAffineTransform",
            withInputParameters: [
                kCIInputImageKey: ciImage,
                kCIInputTransformKey: affineTransform
            ]
        )
        
        let transformedCIImage = transformFilter!.outputImage!
        
        let scale = UIScreen.main.scale
        let previewImageFrame = CGRect(
            x: 0,
            y: 0,
            width: cameraView.frame.width * scale,
            height: cameraView.frame.height * scale
        )
        
        // Draw the transformedCIImage sized by previewImageFrame on GLKView.
        if glContext != EAGLContext.current() {
            EAGLContext.setCurrent(glContext)
        }
        
        glView.bindDrawable()
        ciContext.draw(
            transformedCIImage,
            in: previewImageFrame,
            from: transformedCIImage.extent
        )
        glView.display()
    }
}


















