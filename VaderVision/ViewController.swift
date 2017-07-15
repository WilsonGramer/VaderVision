//
//  ViewController.swift
//  VaderVision
//
//  Created by Wilson Gramer on 7/14/17.
//  Copyright © 2017 Neef.co. All rights reserved.
//

import UIKit
import AVFoundation
import ImageIO

extension UIView {
    // Using a function since `var image` might conflict with an existing variable
    // (like on `UIImageView`)
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
    }
}

extension CGRect{
    init(_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ height:CGFloat) {
        self.init(x:x,y:y,width:width,height:height)
    }
    
}
extension CGSize{
    init(_ width:CGFloat,_ height:CGFloat) {
        self.init(width:width,height:height)
    }
}
extension CGPoint{
    init(_ x:CGFloat,_ y:CGFloat) {
        self.init(x:x,y:y)
    }
}

extension UIImage {
    static func animatedImage(data: Data) -> UIImage? {
        guard let source: CGImageSource = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 1 else {
            return UIImage(data: data)
        }
        
        // Collect key frames and durations
        var frames: [(image: CGImage, delay: Float)] = []
        for i: Int in 0 ..< CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil), let frame = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any], let gif = frame["{GIF}"] as? [String: Any] else {
                continue
            }
            
            // Mimic WebKit approach to determine frame delay
            if let delay = gif["UnclampedDelayTime"] as? Float, delay > 0.0 {
                frames.append((image, delay)) // Prefer "unclamped" delay time
            } else if let delay = gif["DelayTime"] as? Float, delay > 0.0 {
                frames.append((image, delay))
            } else {
                frames.append((image, 0.1)) // WebKit default
            }
        }
        
        // Convert key frames to animated image
        var images: [UIImage] = []
        var duration: Float = 0.0
        for frame in frames {
            let image = UIImage(cgImage: frame.image)
            for _ in 0 ..< Int(frame.delay * 100.0) {
                images.append(image) // Add fill frames
            }
            duration += frame.delay
        }
        return UIImage.animatedImage(with: images, duration: TimeInterval(duration))
    }
}

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var imageView1: UIImageView!
    @IBOutlet weak var imageView2: UIImageView!

    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let sessionQueue = DispatchQueue(label: "session queue",
                                     attributes: [],
                                     target: nil)
    
    var previewLayer : AVCaptureVideoPreviewLayer!
    var videoDeviceInput: AVCaptureDeviceInput!
    var setupResult: SessionSetupResult = .success
    
    enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    ///////////////////////////////////////////////////////////////////////////////
    //MARK: widgets
    @IBOutlet weak var heartbeatGifImageView: UIImageView!
    @IBOutlet weak var heartbeatGifImageView2: UIImageView!
    
    @IBOutlet weak var timeLabelView: UILabel!
    @IBOutlet weak var timeLabelView2: UILabel!
    
    @IBOutlet weak var graphGifImageView: UIImageView!
    @IBOutlet weak var graphGifImageView2: UIImageView!
    
    @IBOutlet weak var graph2GifImageView: UIImageView!
    @IBOutlet weak var graph2GifImageView2: UIImageView!
    
    @IBOutlet weak var zoomFactorLabelView: UILabel!
    @IBOutlet weak var zoomFactorLabelView2: UILabel!
    ///////////////////////////////////////////////////////////////////////////////
    
    var zoomLevel = 1
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        checkAuthorization()
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async { [unowned self] in
            self.configureSession()
        }
        
        imageView1.transform = CGAffineTransform(rotationAngle: 3 * (CGFloat.pi / 2))
        imageView2.transform = CGAffineTransform(rotationAngle: 3 * (CGFloat.pi / 2))
        
        var timer = Timer()
        timer = Timer.scheduledTimer(timeInterval: 0.001, target: self, selector: #selector(self.capturePicture), userInfo: nil, repeats: true)
        
        /*
         Setup animated gifs/widgets.
         */
        heartbeatGifImageView.image  = gif("cardiac")
        heartbeatGifImageView2.image = gif("cardiac")
        
        graphGifImageView.image = gif("graph")   //MEMORY
        graphGifImageView2.image = gif("graph")  //LEAK!
        
        graph2GifImageView.image = gif("graph2")
        graph2GifImageView2.image = gif("graph2")
        
        var timer2 = Timer()
        timer2 = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.timeLabel), userInfo: nil, repeats: true)
        /*
         End setup of gifs/widgets.
         */
    }
    
    
    func gif(_ name: String) -> UIImage {
        let gifUrl = Bundle.main.url(forResource: name, withExtension: "gif")
        let gifData = NSData(contentsOf: gifUrl! as URL) as Data?
        return UIImage.animatedImage(data: gifData!)!
    }
    
    @objc func timeLabel() {
        var date = NSDate()
        var outputFormat = DateFormatter()
        outputFormat.locale = NSLocale(localeIdentifier:"en_US") as Locale!
        outputFormat.dateFormat = "HH:mm:ss"
        timeLabelView.text = outputFormat.string(from: date as Date)
        timeLabelView2.text = outputFormat.string(from: date as Date)
    }
    
    @IBAction func zoom(_ sender: UITapGestureRecognizer) {
        var t = CGAffineTransform.identity
        t = t.rotated(by: 3 * (CGFloat.pi / 2))
        t = t.scaledBy(x: CGFloat(zoomLevel), y: CGFloat(zoomLevel))
        imageView1.transform = t
        imageView2.transform = t
        zoomFactorLabelView.text = "zoomFactor = \(zoomLevel).0"
        zoomFactorLabelView2.text = "zoomFactor = \(zoomLevel).0"
        
        switch zoomLevel {
            case 1:
                self.zoomLevel = 2
            case 2:
                self.zoomLevel = 3
            case 3:
                self.zoomLevel = 1
            default:
                self.zoomLevel = 1
        }
    }
    
    //////////////////////////////////////
    //MARK: Camera code
    //////////////////////////////////////
    
    @objc func capturePicture() {
        let settings = AVCapturePhotoSettings()
        let previewPixelType = settings.availablePreviewPhotoPixelFormatTypes.first!
        let previewFormat = [
            kCVPixelBufferPixelFormatTypeKey as String: previewPixelType,
            kCVPixelBufferWidthKey as String: 160,
            kCVPixelBufferHeightKey as String: 160
        ]
        settings.previewPhotoFormat = previewFormat
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only start the session running if setup succeeded.
                DispatchQueue.main.async { [unowned self] in
                    self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                    self.previewLayer.frame = self.cameraView.bounds
                    self.cameraView.layer.addSublayer(self.previewLayer)
                    self.session.sessionPreset = .medium
                    
                    self.session.startRunning()
                }
                
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.session.stopRunning()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    // MARK: Session Management
    
    func checkAuthorization() {
        /*
         Check video authorization status. Video access is required and audio
         access is optional. If audio access is denied, audio is not recorded
         during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. We suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
    }
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.photo
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera if available, otherwise default to a wide angle camera.
            if let dualCameraDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInDuoCamera, for: AVMediaType.video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) {
                // If the back dual camera is not available, default to the back wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front) {
                /*
                 In some cases where users break their phones, the back wide angle camera is not available.
                 In this case, we should default to the front wide angle camera.
                 */
                defaultVideoDevice = frontCameraDevice
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
            } else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = false
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    @IBAction private func capturePhoto(_ sender: UIButton) {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = false
        if self.videoDeviceInput.device.isFlashAvailable {
            photoSettings.flashMode = .off
        }
        if !photoSettings.availablePreviewPhotoPixelFormatTypes.isEmpty {
            photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.availablePreviewPhotoPixelFormatTypes.first!]
        }
        photoOutput.capturePhoto(with: photoSettings, delegate: self as! AVCapturePhotoCaptureDelegate)
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate Methods
    
    func photoOutput(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?, previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        
        if let error = error {
            //print("Error capturing photo: \(error)")
        } else {
            if let sampleBuffer = photoSampleBuffer, let previewBuffer = previewPhotoSampleBuffer, let dataImage = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: sampleBuffer, previewPhotoSampleBuffer: previewBuffer) {
                
                if let image = UIImage(data: dataImage) {
                    self.imageView1.image = image
                    self.imageView2.image = image
                }
            }
        }
    }
    
    private func updatePreviewLayer(layer: AVCaptureConnection, orientation: AVCaptureVideoOrientation) {
        
        layer.videoOrientation = orientation
        
        previewLayer.frame = self.view.bounds
        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let connection =  self.previewLayer?.connection  {
            
            let currentDevice: UIDevice = UIDevice.current
            
            let orientation: UIDeviceOrientation = currentDevice.orientation
            
            let previewLayerConnection : AVCaptureConnection = connection
            
            if previewLayerConnection.isVideoOrientationSupported {
                
                switch (orientation) {
                case .portrait: updatePreviewLayer(layer: previewLayerConnection, orientation: .portrait)
                
                    break
                    
                case .landscapeRight: updatePreviewLayer(layer: previewLayerConnection, orientation: .landscapeLeft)
                
                    break
                    
                case .landscapeLeft: updatePreviewLayer(layer: previewLayerConnection, orientation: .landscapeRight)
                
                    break
                    
                case .portraitUpsideDown: updatePreviewLayer(layer: previewLayerConnection, orientation: .portraitUpsideDown)
                
                    break
                    
                default: updatePreviewLayer(layer: previewLayerConnection, orientation: .portrait)
                
                    break
                }
            }
        }
    }
}
