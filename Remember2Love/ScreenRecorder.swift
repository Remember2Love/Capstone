//
//  ScreenRecorder.swift
//  Remember2Love
//
//  Created by Karan Sabharwal on 2020-03-18.
//  Copyright © 2020 Remember2Love. All rights reserved.
//
// this Swift file handles screen recording interactions with items

import Foundation
import AVKit
import ReplayKit

class ScreenRecorder {

    var assetWriter : AVAssetWriter! // AVAssetWriter object/receiver that will perform the media-writing to an AV filetype
    var videoInput : AVAssetWriterInput! // AVAssetWriterInput object that will perform the writing to the output file of the respective AVAssetWriter object
    
    var recordFlag = true
    
    let r2lFile = R2LFile()
    
    func startRecording(fileName: String){
        
        if (self.recordFlag){
            let fileURL = URL(fileURLWithPath: r2lFile.filePath(fileName)) // create a URL object from string filepath
            
            assetWriter = try! AVAssetWriter(outputURL: fileURL, fileType: AVFileType.mp4)
            
            let videoSettings : [String : Any] = [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoWidthKey : UIScreen.main.bounds.size.width,
                AVVideoHeightKey : UIScreen.main.bounds.size.height
            ] // settings for the captured video stored in the file
            
            videoInput  = AVAssetWriterInput (mediaType: AVMediaType.video, outputSettings: videoSettings) // AVAssetWriterInput object that will be written to the AVAssetWriter's output file with configured settings
            videoInput.expectsMediaDataInRealTime = true // we are feeding in input from the camera continuously/in realtime
            assetWriter.add(videoInput) // add the created AVAssetWriterInput object as input to the AVAssetWriter object
        }
        // start the screen capture (audio and video)
        RPScreenRecorder.shared().startCapture(handler: { (audioVideoSample, bufferType, error) in
            print("Started recording with filename: \(fileName)")
            
            
            if (self.recordFlag){
        
                if (CMSampleBufferDataIsReady(audioVideoSample)){ // ensure audio/video data is ready in the buffer
                    
                    DispatchQueue.main.async {
                        if(self.assetWriter.status == AVAssetWriter.Status.unknown){ //check if AVAssetWriter is in a state to write to its output file
                            self.assetWriter.startWriting() // start writing to the output file
                            self.assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(audioVideoSample)) // grab source from sample buffer holding video and audio data
                            
                        }
                    }
                    
                    
                    if self.assetWriter.status == AVAssetWriter.Status.failed {
                        print("Error occured, status = \(self.assetWriter.status.rawValue), \(self.assetWriter.error!.localizedDescription) \(String(describing: self.assetWriter.error))")
                        return
                    } // handle error in case asset write to output file fails
                    
                    if(bufferType == .video){ // write the sample buffer data to the AVAssetWriterInput object
                        
                        if(self.videoInput.isReadyForMoreMediaData){
                            self.videoInput.append(audioVideoSample) // write the sample buffer data if the AVAssetWriterInput is ready to receive/accept
                        }
                        
                    }
                }
            }
                
                    
        }) { (error) in
            print("Error: \(error)")
        }
    }
    
    func stopRecording(){
        
        RPScreenRecorder.shared().stopCapture { (error) in
            if let stopError = error{
                print("Error stopping capture: \(stopError)")
            }
                self.assetWriter.finishWriting {
                    print(self.r2lFile.retrieveRecordings())
                }
        }
    }
    
}
