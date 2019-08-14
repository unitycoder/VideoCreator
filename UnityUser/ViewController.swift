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
import MetalKit
import Metal

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
        
        let loader = MTKTextureLoader(device: ViewController.sharedMtlDevive)
        //         testTex: MTLTexture
        do {
            let ui: UIImage = UIImage(named: "test.jpeg")!
            let cg: CGImage = ui.cgImage!
            testTex = try loader.newTexture(cgImage: cg, options: nil)
        } catch let error {
            print("erro: \(error)")
            return
        }
        
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, ViewController.sharedMtlDevive, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        self.makeVideoCreator()
        self.captureSession.startRunning()
        print("start running")
    }
    
    var capturedImageTextureCache: CVMetalTextureCache!
    
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
    
    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    var context = CIContext()
    
    var testTex: MTLTexture!
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !self.isRecording {
            return
        }
        
        if output is AVCaptureAudioDataOutput {
            self.videoCreator?.write(sample: sampleBuffer, isVideo: false)
            return
        }
        
        testTex = sampleBuffer.toMtlTexture!
        
        guard let nowTime = videoCreator?.nowTime else {
            return
        }
        
        guard let ci2 = CIImage(mtlTexture: testTex, options: nil) else {
            return
        }
        
        let options = [ kCVPixelBufferIOSurfacePropertiesKey: [:] ] as [String : Any]
        var tmpRecodePixelBuffer: CVPixelBuffer? = nil
        let _ = CVPixelBufferCreate(nil,
                                    testTex.width,
                                    testTex.height,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    options as CFDictionary,
                                    &tmpRecodePixelBuffer)
        guard let recodePixelBuffer = tmpRecodePixelBuffer else {
            return
        }

        CVPixelBufferLockBaseAddress(recodePixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        context.render(ci2, to: recodePixelBuffer)
        
        var opDescription: CMVideoFormatDescription?
        let status2 = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
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
        sampleTiming.presentationTimeStamp = nowTime
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
