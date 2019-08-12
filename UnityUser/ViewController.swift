//
//  ViewController.swift
//  UnityUser
//
//  Created by fuziki on 2019/08/12.
//  Copyright © 2019 fuziki.factory. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary
import VideoCreator

class ViewController: UIViewController {
    
    var captureSession: AVCaptureSession!
    var videoDevice: AVCaptureDevice!
    var audioDevice: AVCaptureDevice!
    var videoCreator: VideoCreator? = nil
    var videoConfig: VideoCreator.VideoConfig!
    var audioConfig: VideoCreator.AudioConfig!
    
    var tmpFilePath: String!
    
    var isRecording: Bool = false
    
    static var sharedMtlDevive: MTLDevice = MTLCreateSystemDefaultDevice()!
    
    @IBOutlet weak var checkView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            try AVAudioSession.sharedInstance().setPreferredSampleRate(44100.0)
            try AVAudioSession.sharedInstance().setPreferredInputNumberOfChannels(1)
        } catch let error {
            print("failed init aduio session error: \(error)")
        }
        
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .hd1920x1080
        guard let videoDevice = AVCaptureDevice.default(for: AVMediaType.video),
            let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio),
            let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
            let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
                print("failed init capture device")
                return
        }
        
        videoConfig = VideoCreator.VideoConfig(codec: AVVideoCodecType.h264,
                                               width: 1920,
                                               height: 1080)
        audioConfig = VideoCreator.AudioConfig(format: kAudioFormatMPEG4AAC,
                                               channel: 1,
                                               samplingRate: 44100.0,
                                               bitRate: 128000)
        
        videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
        
        self.videoDevice = videoDevice
        self.audioDevice = audioDevice
        
        captureSession.addInput(videoInput)
        captureSession.addInput(audioInput)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings
            = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)] as [String : Any]
//            = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_422YpCbCr8FullRange)] as [String : Any]
//            = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_32BGRA)] as [String : Any]
        captureSession.addOutput(videoOutput)
        
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        captureSession.addOutput(audioOutput)
        
        let videoLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoLayer.frame = view.bounds
        videoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        checkView.layer.addSublayer(videoLayer)
        
        guard let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return
        }
        self.tmpFilePath = "\(dir)/tmpVideo.mov"
        
        self.makeVideoCreator()
        self.captureSession.startRunning()
        print("start running")
    }
    
    @IBAction func start(_ sender: Any) {
        print("start recording")
        isRecording = true
    }
    
    @IBAction func pause(_ sender: Any) {
        
    }
    
    @IBAction func resume(_ sender: Any) {
        
    }
    
    @IBAction func stop(_ sender: Any) {
        print("stop recording")
        if !self.isRecording {
            return
        }
        self.videoCreator?.finish(completionHandler: { [weak self] in
            guard let me = self else {
                return
            }
            ALAssetsLibrary().writeVideoAtPath(toSavedPhotosAlbum: URL(fileURLWithPath: me.tmpFilePath),
                                               completionBlock: { (url: URL?, error: Error?) -> Void in
                                                print("url: \(url), error: \(error)")
                                                me.videoCreator = nil
                                                me.makeVideoCreator()
            })
        })
        self.isRecording = false
    }
    
    func makeVideoCreator() {
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: self.tmpFilePath) {
            do {
                try fileManager.removeItem(atPath: self.tmpFilePath)
            } catch let error {
                print("makeVideoCreator \(error)")
            }
        }
        self.videoCreator = VideoCreator(url: self.tmpFilePath, videoConfig: self.videoConfig, audioConfig: self.audioConfig)
    }
    
    var factory = CMSampleBuffer.VideoFactory()
    var offset: CMTime? = nil
    
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !self.isRecording {
            return
        }
        if output is AVCaptureAudioDataOutput {
            self.videoCreator?.write(sample: sampleBuffer,
                                     isVideo: false)
            return
        }
        
        guard let startTime = videoCreator?.startTime else {
            return
        }
        
        let t1 = CMTime(value: CMTimeValue(Int(Date().timeIntervalSince1970 * 1000000000)),
                        timescale: 1000000000,
                        flags: .init(rawValue: 3),
                        epoch: 0)
        
        if self.offset == nil {
            self.offset = CMTimeSubtract(t1, startTime)
        }
        
        guard let offset = self.offset,
            let tex: MTLTexture = sampleBuffer.toMtlTexture,
            let newBuff = factory.createSampleBufferBy(mtlTexture: tex, timeStamp: CMTimeSubtract(t1, offset)) else {
            return
        }
        
        self.videoCreator?.write(sample: newBuff, isVideo: true)
        
    }
}

extension CMSampleBuffer {
    var toMtlTexture: MTLTexture? {
        guard let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(self) else {
            print("failed CMSampleBufferGetImageBuffer")
            return nil
        }
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let inputImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(mtlDevice: ViewController.sharedMtlDevive)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                         width: width,
                                                                         height: height,
                                                                         mipmapped: false)
        textureDescriptor.usage = .unknown
        let toTexture = ViewController.sharedMtlDevive.makeTexture(descriptor: textureDescriptor)
        context.render(inputImage, to: toTexture!, commandBuffer: nil, bounds: inputImage.extent, colorSpace: colorSpace)
        return toTexture!
    }
}

extension CMSampleBuffer {
    public class VideoFactory {
        public let context = CIContext()
        
        init() {
        }
        
        public static func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
            var pixelBuffer: CVPixelBuffer?
            let options = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as [String : Any]
            let status = CVPixelBufferCreate(nil,
                                             width,
                                             height,
                                             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
//                                             kCVPixelFormatType_422YpCbCr8FullRange,
//                                             kCVPixelFormatType_32BGRA,
                                             options as CFDictionary,
                                             &pixelBuffer)
            if status != kCVReturnSuccess {
                return nil
            }
            return pixelBuffer
        }
        
        public func createSampleBufferBy(mtlTexture: MTLTexture, timeStamp: CMTime? = nil) -> CMSampleBuffer? {
            guard let pixelBuffer = VideoFactory.createPixelBuffer(width: mtlTexture.width, height: mtlTexture.height) else {
                return nil
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let ci = CIImage(mtlTexture: mtlTexture, options: nil)!
            context.render(ci, to: pixelBuffer)
            var opDescription: CMVideoFormatDescription?
            var status =
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                             imageBuffer: pixelBuffer,
                                                             formatDescriptionOut: &opDescription)
            if status != noErr {
                return nil
            }
            guard let description: CMVideoFormatDescription = opDescription else {
                return nil
            }
            var sampleBufferOut: CMSampleBuffer?
            var sampleTiming = CMSampleTimingInfo()
            sampleTiming.presentationTimeStamp = CMTime(value: CMTimeValue(Int(Date().timeIntervalSince1970 * 30000.0)),
                                                        timescale: 30000,
                                                        flags: .init(rawValue: 3),
                                                        epoch: 0)
            if let t = timeStamp {
                sampleTiming.presentationTimeStamp = t
            }
            status = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                        imageBuffer: pixelBuffer,
                                                        dataReady: true,
                                                        makeDataReadyCallback: nil,
                                                        refcon: nil,
                                                        formatDescription: description,
                                                        sampleTiming: &sampleTiming,
                                                        sampleBufferOut: &sampleBufferOut)
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return sampleBufferOut
        }
        
        public func createSampleBufferBy(pixelBuffer: CVPixelBuffer, timeStamp: CMTime) -> CMSampleBuffer? {
            var opDescription: CMVideoFormatDescription?
            var status =
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                             imageBuffer: pixelBuffer,
                                                             formatDescriptionOut: &opDescription)
            if status != noErr {
                return nil
            }
            guard let description: CMVideoFormatDescription = opDescription else {
                return nil
            }
            var sampleBufferOut: CMSampleBuffer?
            var sampleTiming = CMSampleTimingInfo()
            sampleTiming.presentationTimeStamp = CMTime(value: CMTimeValue(Int(Date().timeIntervalSince1970 * 30000.0)),
                                                        timescale: 30000,
                                                        flags: .init(rawValue: 3),
                                                        epoch: 0)
            sampleTiming.presentationTimeStamp = timeStamp
            status = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                        imageBuffer: pixelBuffer,
                                                        dataReady: true,
                                                        makeDataReadyCallback: nil,
                                                        refcon: nil,
                                                        formatDescription: description,
                                                        sampleTiming: &sampleTiming,
                                                        sampleBufferOut: &sampleBufferOut)
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return sampleBufferOut
        }
    }
}
