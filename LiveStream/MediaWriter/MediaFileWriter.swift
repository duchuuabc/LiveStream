//
//  FileWriter.swift
//  RecordCamera
//
//  Created by CPU12015 on 10/2/19.
//  Copyright © 2019 CPU12015. All rights reserved.
//

import UIKit
import AVFoundation

enum MediaWriterFileType : Int{
    case MP4
    
    case M4V
    
    case M4A
}

class MediaFileWriter: NSObject {
    private let writerQueue = DispatchQueue(label: "file writer queue")
    
    private(set) public var expectsMediaDataInRealTime : Bool = true
    private(set) public var fileExt : String?
    private(set) public var fileType : MediaWriterFileType?
    
    public var status : AVAssetWriter.Status{
        get{
            return assetWriter?.status ?? AVAssetWriter.Status.unknown
        }
    }
    public var error : Error?{
        get{
            return assetWriter?.error
        }
    }
    
    private var videoAssetWriterInput: AVAssetWriterInput?
    private var audioAssetWriterInput: AVAssetWriterInput?
    private var assetWriter: AVAssetWriter?
    private var sessionAtSourceTime: CMTime?
    
    init(fileType : MediaWriterFileType){
        super.init()
        
        if setupFileWriter(fileType: fileType){
        }
    }
    
    init(fileType : MediaWriterFileType, fileExt : String){
        super.init()
        
        if setupFileWriter(fileType: fileType, fileExt: fileExt){
        }
    }
    
    init(videoWriterInput : AVAssetWriterInput?, audioWriterInput : AVAssetWriterInput?, fileType : MediaWriterFileType){
        super.init()
        
        self.videoAssetWriterInput = videoWriterInput
        self.audioAssetWriterInput = audioWriterInput
        
        if setupFileWriter(fileType: fileType){
        }
    }
    
    init(videoWriterInput : AVAssetWriterInput?, audioWriterInput : AVAssetWriterInput?, fileType : MediaWriterFileType, fileExt : String){
        super.init()
        
        self.videoAssetWriterInput = videoWriterInput
        self.audioAssetWriterInput = audioWriterInput
        
        if setupFileWriter(fileType: fileType, fileExt: fileExt){
        }
    }
    
    /**
     This func must be called before creating data input
     */
    private func setupFileWriter(fileType : MediaWriterFileType) -> Bool{
        return setupFileWriter(fileType: fileType, fileExt: MediaFileWriter.getFileExtentionFrom(fileType: fileType))
    }
    
    /**
     This func must be called before creating data input
     */
    private func setupFileWriter(fileType : MediaWriterFileType, fileExt : String) -> Bool{
        var success = true
        
        writerQueue.sync {
            // Create fileURL
            let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
            let fileName = "\(Date().timeIntervalSince1970)" + fileExt
            let filePath = path + "/" + fileName
            let fileURL = URL(fileURLWithPath: filePath)
            
            do{
                assetWriter = try AVAssetWriter(url:fileURL, fileType: MediaFileWriter.getAVFileTypeFrom(fileType: fileType))
            }catch{
                success = false
                print("create AVAssetWriter failed")
            }
        }
        
        return success
    }
    
    //MARK: Create data input
    
    func createNewDefaultVideoInput() -> Bool{
        if #available(iOS 11.0, *) {
            return createNewVideoInput(videoCodecType: .h264, outputSize: CGSize(width: 640, height: 480))
        } else {
            return false
            // Fallback on earlier versions
        }
    }
    
    func createNewDefaultAudioInput() -> Bool{
        
        return createNewAudioInput(audioFormat: kAudioFormatMPEG4AAC, numberOfChannels: 1, sampleRate: 44100)
    }
    
    func createNewVideoInput(videoCodecType: AVVideoCodecType, outputSize : CGSize) -> Bool{
        var success = false
        
        writerQueue.sync {
            if status == .unknown{
                // Assetwriter is not currently known
                videoAssetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: videoCodecType,
                    AVVideoWidthKey: outputSize.width,
                    AVVideoHeightKey: outputSize.height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 2300000,
                    ],
                ])
                videoAssetWriterInput?.expectsMediaDataInRealTime = expectsMediaDataInRealTime
                
                if videoAssetWriterInput != nil, (assetWriter?.canAdd(videoAssetWriterInput!))! {
                    assetWriter?.add(videoAssetWriterInput!)
                    success = true
                }
            }
        }
        
        return success
    }
    
    func createNewAudioInput(audioFormat : AudioFormatID, numberOfChannels : UInt8, sampleRate : Int) -> Bool{
        var success = false
        
        writerQueue.sync {
            if status == .unknown{
                // Assetwriter is not currently known
                audioAssetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: audioFormat,
                    AVNumberOfChannelsKey: numberOfChannels,
                    AVSampleRateKey: sampleRate,
                    AVEncoderBitRateKey: 64000,
                ])
                
                audioAssetWriterInput?.expectsMediaDataInRealTime = expectsMediaDataInRealTime
                
                if audioAssetWriterInput != nil, (assetWriter?.canAdd(audioAssetWriterInput!))! {
                    assetWriter?.add(audioAssetWriterInput!)
                    success = true
                }
            }
        }
        
        return success
    }
    
    // MARK: Control
    
    func startWriting() -> Bool{
        var success = false
        
        writerQueue.sync {
            if assetWriter != nil{
                success = (assetWriter?.startWriting())!
            }
        }
        
        return  success
    }
    
    /**
     @method finishWritingWithCompletionHandler:
     @abstract
     Marks all unfinished inputs as finished and completes the writing of the output file.
     After call this function, this Object will be reseted
     */
    func finishWriting(completion : @escaping (URL?) -> Void){
        writerQueue.async {
            if self.status == .writing{
                self.assetWriter?.finishWriting {
                    
                    [weak self] in guard let url = self?.assetWriter?.outputURL else { return }
                    
                    completion(url)
                    
                    self?.clearAll()
                }
            }
        }
    }
    
    private func clearAll(){
        assetWriter = nil
        videoAssetWriterInput = nil
        audioAssetWriterInput = nil
        expectsMediaDataInRealTime = true
        fileType = nil
        fileExt = nil
        sessionAtSourceTime = nil
    }
    
    //MARK: AppendSample
    
    func videoAppend(sampleBuffer : CMSampleBuffer){
        writerQueue.async {
            if self.videoAssetWriterInput == nil, self.status != .writing{
                return
            }
            if self.sessionAtSourceTime == nil{
                self.sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetWriter?.startSession(atSourceTime: self.sessionAtSourceTime!)
            }
            
            if self.videoAssetWriterInput!.isReadyForMoreMediaData{
                self.videoAssetWriterInput?.append(sampleBuffer)
            }
        }
    }
    
    func audioAppend(sampleBuffer : CMSampleBuffer){
        writerQueue.async {
            if self.audioAssetWriterInput == nil, self.status != .writing{
                return
            }
            if self.sessionAtSourceTime == nil{
                self.sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetWriter?.startSession(atSourceTime: self.sessionAtSourceTime!)
            }
            
            if  self.audioAssetWriterInput!.isReadyForMoreMediaData{
                self.audioAssetWriterInput?.append(sampleBuffer)
            }
        }
    }
    
}

extension MediaFileWriter{
    private class func getFileExtentionFrom(fileType : MediaWriterFileType) -> String{
        var fileExt : String
        
        switch fileType {
        case .MP4:
            fileExt = ".mp4"
        case .M4V:
            fileExt = ".m4v"
        case .M4A:
            fileExt = ".m4a"
        }
        
        return fileExt
    }
    
    private class func getAVFileTypeFrom(fileType : MediaWriterFileType) -> AVFileType{
        var type : AVFileType
        
        switch fileType {
        case .MP4:
            type = .mp4
        case .M4V:
            type = .m4v
        case .M4A:
            type = .m4a
        }
        
        return type
    }
    
}
