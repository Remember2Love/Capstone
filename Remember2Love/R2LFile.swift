//
//  R2LFile.swift
//  Remember2Love
//
//  Created by Karan Sabharwal on 2020-03-18.
//  Copyright © 2020 CompanyName. All rights reserved.
//

import Foundation

class R2LFile {
    
    // create the custom recordings folder in the application data directory that will store captured recordings
    func createRecordingsFolder(){
        let appDocumentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first // get the directory for the application using the user directory as a base/starting point
            
            if let documentsDirectory = appDocumentsDirectory {
                
                let recordingsPath = documentsDirectory.appending("/Recordings")
                
                let fileManager = FileManager.default
                
                if !fileManager.fileExists(atPath: recordingsPath) {
                    do {
                        try fileManager.createDirectory(atPath: recordingsPath, withIntermediateDirectories: false, attributes: nil)
                    } catch{
                        print("Error creating directory: \(error)")
                    }
                }
                
            }
    }
    
    // function to take in a recording filename and generate a filepath
    func filePath(_ filename: String) -> String {
        createRecordingsFolder() // creates the directory in case it does not exist
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true) // grab the path to the app documents folder
        let documentsDirectory = documentsPath[0] as String // grab the first result
        let filePath : String = "\(documentsDirectory)/Recordings/\(filename).mp4" // generate the full file path
        return filePath
    }
    
    // function to retrieve the contents of the directory that holds the screen recordings
    func retrieveRecordings() -> [URL]{
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let recordingsPath = documentsDirectory?.appendingPathComponent("/Recordings")
        let directoryContents = try! FileManager.default.contentsOfDirectory(at: recordingsPath!, includingPropertiesForKeys: nil, options: [])
        return directoryContents
    }
}
