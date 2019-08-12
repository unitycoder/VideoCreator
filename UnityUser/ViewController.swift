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
//            = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_422YpCbCr8FullRange)] as [String : Any]
            = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)] as [String : Any]
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
        
        let time: CMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let tex: MTLTexture = sampleBuffer.toMtlTexture,
            let newBuff = factory.createSampleBufferBy(mtlTexture: tex, timeStamp: time) {
            CMSampleBufferSetOutputPresentationTimeStamp(newBuff, newValue: time)
            CMSampleBufferSetDataReady(newBuff)
            
            let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            
            let sampleBufferByCVPixelBuffer = factory.createSampleBufferBy(pixelBuffer: imageBuffer, timeStamp: time)!  //ok
            

            
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            let ci = CIImage(cvPixelBuffer: imageBuffer)
//            print("0: ", imageBuffer)

            let mtlcontext = CIContext(mtlDevice: ViewController.sharedMtlDevive)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                             width: width,
                                                                             height: height,
                                                                             mipmapped: false)
            textureDescriptor.usage = .unknown
            let toTexture = ViewController.sharedMtlDevive.makeTexture(descriptor: textureDescriptor)!
            mtlcontext.render(ci, to: toTexture, commandBuffer: nil, bounds: ci.extent, colorSpace: colorSpace)
            
            let ci2 = CIImage(mtlTexture: toTexture, options: nil)!
            
            
            
            
            let options = [
//                kCVPixelBufferCGImageCompatibilityKey: true,
//                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
                ] as [String : Any]
            
            var tmpRecodePixelBuffer: CVPixelBuffer? = nil
            let _ = CVPixelBufferCreate(nil,
                                             width,
                                             height,
//                                             kCVPixelFormatType_422YpCbCr8FullRange,
                                             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
//                                             kCVPixelFormatType_32BGRA,
                                        options as CFDictionary,
                                             &tmpRecodePixelBuffer)
            let recodePixelBuffer = tmpRecodePixelBuffer!
            CVPixelBufferLockBaseAddress(recodePixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            factory.context.render(ci2, to: recodePixelBuffer)
            
//            print("1", recodePixelBuffer)
            
            var opDescription: CMVideoFormatDescription?
            let status2 =
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                             imageBuffer: recodePixelBuffer,
                                                             formatDescriptionOut: &opDescription)
            if status2 != noErr {
                print("\(#line)")
            }
            guard let description: CMVideoFormatDescription = opDescription else {
                print("\(#line)")
                return
            }
            
            var tmp: CMSampleBuffer? = nil
            var sampleTiming = CMSampleTimingInfo()
            sampleTiming.presentationTimeStamp = time
            let _ = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: recodePixelBuffer,
                                                        dataReady: true,
                                                        makeDataReadyCallback: nil,
                                                        refcon: nil,
                                                        formatDescription: description,
                                                        sampleTiming: &sampleTiming,
                                                        sampleBufferOut: &tmp)
            self.videoCreator?.write(sample: tmp!,
                                     isVideo: true)
            CVPixelBufferUnlockBaseAddress(recodePixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        }
    }

    func printCVPixelBuffer(buff imageBuffer: CVPixelBuffer) {
        let type = CVPixelBufferGetPixelFormatType(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let dataSize = CVPixelBufferGetDataSize(imageBuffer)
        let planeCount = CVPixelBufferGetPlaneCount(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let widthOfPlane0 = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
        let widthOfPlane1 = CVPixelBufferGetWidthOfPlane(imageBuffer, 1)
        let heightOfPlane0 = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
        let heightOfPlane1 = CVPixelBufferGetHeightOfPlane(imageBuffer, 1)
        let bytesPerRowOfPlane0 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
        let bytesPerRowOfPlane1 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1)
        print("type: \(type), width: \(width), height: \(height), dataSize: \(dataSize), planeCount: \(planeCount), bytesPerRow: \(bytesPerRow), widthOfPlane0: \(widthOfPlane0), \(widthOfPlane1), heightOfPlane: \(heightOfPlane0), \(heightOfPlane1), bytesPerRowOfPlane: \(bytesPerRowOfPlane0), \(bytesPerRowOfPlane1)")
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
            let status = CVPixelBufferCreate(nil,
                                             width,
                                             height,
//                                             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                             kCVPixelFormatType_32BGRA,
                                             nil,
                                             &pixelBuffer)
            if status != kCVReturnSuccess {
                return nil
            }
            return pixelBuffer
        }
        
        public func createSampleBufferBy(mtlTexture: MTLTexture, timeStamp: CMTime) -> CMSampleBuffer? {
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
