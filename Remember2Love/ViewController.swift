//
//  ViewController.swift
//  Remember2Love
//
//  Created by Karan Sabharwal on 2020-03-17.
//  Copyright © 2020 Remember2Love. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import AVKit
import Speech
import VisionKit
import Foundation
import AVFoundation
import EventKit

class ViewController: UIViewController, ARSCNViewDelegate, SFSpeechRecognizerDelegate { // this view conforms to the ARSCNViewDelegate Protocol

    // SCENE
    @IBOutlet var sceneView: ARSCNView! // an outlet storing a reference to the ARSCNView on the storyboard
    let bubbleDepth : Float = 0.01 // the 'depth' of 3D text
    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    
    //Text Detection
    var request: VNRecognizeTextRequest!
    var textOrientation = CGImagePropertyOrientation.up
    
    // COREML
    var visionRequests = [VNRequest()] // create an array of VNRequests from the ML Model
    let dispatchQueueML = DispatchQueue(label: "MLDispatchQueue") // A Custom Serial Queue for ML Tasks
    let dispatchQueueSR = DispatchQueue(label: "SRDispatchQueue") // A Custom Serial Queue for SR Tasks
    let dispatchQueueSpeech = DispatchQueue(label: "SpeechDispatchQueue") // A Custom Serial Queue for Speech Recognition Tasks
    let dispatchQueueParallel = DispatchQueue(label: "ParallelQueue", attributes: .concurrent)
    var tylenolFlag : Bool = false
    var advilFlag : Bool = false
    @IBOutlet weak var debugTextView: UITextView!
    
    //let storage = Storage.storage(url:"gs://videostorage-27480.appspot.com")
    
    // AVSpeechSynthesizer Object
    let synthesizer = AVSpeechSynthesizer()
    
    // Speech to Text Variables
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    var allowed : Bool = false
    var speechRecognition : Bool = true
    var spokenPhrase = ""
    
    // ScreenRecorder object
    let screenRecorder = ScreenRecorder()
    
    // R2LFile Object
    let file = R2LFile()
    
    // Object List
    var objectList : [String] = []
    
    // recording access flag
    var recordingFinished : Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        
        //Calendar
        let eventStore = EKEventStore()
            
//        switch EKEventStore.authorizationStatus(for: .event)
//        {
//            case .authorized:
//                //insertEvent(store: eventStore)
//
//                case .denied:
//                    print("Access denied")
//                case .notDetermined:
//                // 3
//                    eventStore.requestAccess(to: .event, completion:
//                      {[weak self] (granted: Bool, error: Error?) -> Void in
//                          if granted {
//                            self!.insertEvent(store: eventStore)
//                          } else {
//                                print("Access denied")
//                          }
//                    })
//                    default:
//                        print("Case default")
//        }
        
        //Commented out for now
        //insertEvent(store: eventStore)
                
        // speak welcome message
        let welcomeMessage = "Welcome to Remember2Love"
        let utterance = AVSpeechUtterance(string: welcomeMessage)
        utterance.rate = 0.5
        synthesizer.speak(utterance)
        
        speechRecognizer.delegate = self
        // Asynchronously make the authorization request.
        SFSpeechRecognizer.requestAuthorization { authStatus in

            // Divert to the app's main thread so that the UI
            // can be updated.
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.allowed = true
                    
                case .denied:
                    self.allowed = false
                    
                case .restricted:
                    self.allowed = false
                    
                case .notDetermined:
                    self.allowed = false
                    
                default:
                    self.allowed = false
                }
            }
        }
        
        sceneView.delegate = self // set the ARSCNView's delegate as the main view
        
        let scene = SCNScene() // the actual container for the 3D nodes wanting to be rendered in AR
        
        sceneView.scene = scene // pair the ARSCNView to the created SCNScene
        
        // Enable Default Lighting - makes the 3D text a bit poppier.
        sceneView.autoenablesDefaultLighting = true
        
        // Set up Vision Model
        // creates the ML Model Container for Inceptionv3 ML Model
        guard let selectedModel = try? VNCoreMLModel(for: Inceptionv3().model) else { // (Optional) This can be replaced with other models on https://developer.apple.com/machine-learning/
            fatalError("Could not create ML container model")
        }
        
        // Create the folder to hold the interaction recordings
        file.createRecordingsFolder()
        
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler) // generates the image classification request for the ML model
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop // Crop from centre of images and scale to appropriate size.
        visionRequests = [classificationRequest]
        
        dispatchQueueParallel.async {
             // Begin Loop to Update CoreML
            self.loopCoreMLUpdate()
        }
       
        dispatchQueueParallel.asyncAfter(deadline: .now() + 10, execute: {
            // Begin Loop for Speech Recognition
            self.loopSpeechRecognition()
        })
      
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        // Enable plane detection
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }

    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Do any desired updates to SceneKit here.
        }
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    func insertEvent(store: EKEventStore)
    {
        // 1
        let calendars = store.calendars(for: .event)
            
        for calendar in calendars
        {
            // 2
            //if calendar.title == "ioscreator" {
                // 3
                let startDate = Date()
                // 2 hours
                let endDate = startDate.addingTimeInterval(2 * 60 * 60)
                    
                // 4
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                    
                event.title = "New Meeting"
                event.startDate = startDate
                event.endDate = endDate
                    
                // 5
                do {
                    try store.save(event, span: .thisEvent)
                }
                catch {
                   print("Error saving event in calendar")
                    
            }
        }
    }
    
    func recognizeTextHandler(request: VNRequest, error: Error?)
    {
        guard let results = request.results as? [VNRecognizedTextObservation] else {
            return
        }
        
        let maximumCandidates = 1
        
        for visionResult in results {
            guard let candidate = visionResult.topCandidates(maximumCandidates).first else { continue }
            
            print("Inside text detection")
            print(candidate.string)
            
            if ((candidate.string.contains("TYLEN") || candidate.string.contains("TY") || candidate.string.contains("TYL") || candidate.string.contains("TYLENO") || candidate.string.contains("YLEN") || candidate.string.contains("LENO")) && !self.tylenolFlag)
            {
                self.tylenolFlag = true
            } else if ((candidate.string.contains("Advil") || candidate.string.contains("Ad")) && !self.advilFlag) {
                self.advilFlag = true
            }
        }
    }

    func displayARText(_ itemString : String) {
        // Get Screen Centre
        let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY - 50) // apply offset to y value to make anchor point of text above object
        
        let arHitTestResults : [ARHitTestResult] = sceneView.hitTest(screenCentre, types: [.featurePoint, .estimatedHorizontalPlane]) // Alternatively, we could use '.existingPlaneUsingExtent' for more grounded hit-test-points.
        
        if let closestResult = arHitTestResults.first {
            // Get Coordinates of HitTest
            let transform : matrix_float4x4 = closestResult.worldTransform
            let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // Create 3D Text
            let node : SCNNode = createNewBubbleParentNode(itemString)
            sceneView.scene.rootNode.addChildNode(node)
            node.position = worldCoord
        }
    }
    
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        // Warning: Creating 3D Text is susceptible to crashing. To reduce chances of crashing; reduce number of polygons, letters, smoothness, etc.
        
        // TEXT BILLBOARD CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        // BUBBLE-TEXT
        let bubble = SCNText(string: text, extrusionDepth: CGFloat(bubbleDepth))
        var font = UIFont(name: "Futura", size: 0.15)
        font = font?.withTraits(traits: .traitBold)
        bubble.font = font
        bubble.alignmentMode = convertFromCATextLayerAlignmentMode(CATextLayerAlignmentMode.center)
        bubble.firstMaterial?.diffuse.contents = UIColor.red
        bubble.firstMaterial?.specular.contents = UIColor.white
        bubble.firstMaterial?.isDoubleSided = true
        // bubble.flatness // setting this too low can cause crashes.
        bubble.chamferRadius = CGFloat(bubbleDepth)
        
        // BUBBLE NODE
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        // Centre Node - to Centre-Bottom point
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, bubbleDepth/2)
        // Reduce default text size
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        // CENTRE POINT NODE
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        let sphereNode = SCNNode(geometry: sphere)
        
        // BUBBLE PARENT NODE
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        bubbleNodeParent.addChildNode(sphereNode)
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
    
    func createVideoURL(_ text: String) -> String {
        // get the current date and time
        let currentDateTime = Date()

        // get the user's calendar
        let userCalendar = Calendar.current

        // choose which date and time components are needed
        let requestedComponents: Set<Calendar.Component> = [
            .year,
            .month,
            .day,
            .hour,
            .minute,
            .second
        ]

        // get the components
        let dateTimeComponents = userCalendar.dateComponents(requestedComponents, from: currentDateTime)
        
        //creates a unique url
        let videoURL = "\(text)_" + "\(dateTimeComponents.year ?? 0)_" + "\( dateTimeComponents.month ?? 0)_" + "\(dateTimeComponents.day ?? 0)_" + "\(dateTimeComponents.hour ?? 0)_" + "\(dateTimeComponents.minute ?? 0)" + ".jpg"
        
        print(videoURL)
        
        return videoURL
    }
    
    private func startRecording() throws {
       // Cancel the previous task if it's running.
       recognitionTask?.cancel()
       self.recognitionTask = nil
       
       // Configure the audio session for the app.
       let audioSession = AVAudioSession.sharedInstance()
       try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
       //try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
       let inputNode = audioEngine.inputNode

       // Create and configure the speech recognition request.
       recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
       guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object") }
       recognitionRequest.shouldReportPartialResults = true
       
       // Keep speech recognition data on device
       if #available(iOS 13, *) {
           recognitionRequest.requiresOnDeviceRecognition = false
       }
       
       // Create a recognition task for the speech recognition session.
       // Keep a reference to the task so that it can be canceled.
       recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
           var isFinal = false
           
           if let result = result {
               // Update the text view with the results.
               print(result.bestTranscription.formattedString)
               self.spokenPhrase = result.bestTranscription.formattedString
               isFinal = result.isFinal
               //print("Text \(result.bestTranscription.formattedString)")
           }
           
           if error != nil || isFinal {
               // Stop recognizing speech if there is a problem.
               self.audioEngine.stop()
               inputNode.removeTap(onBus: 0)

               self.recognitionRequest = nil
               self.recognitionTask = nil
           }

       }

       // Configure the microphone input.
       let recordingFormat = inputNode.outputFormat(forBus: 0)
       inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
           self.recognitionRequest?.append(buffer)
       }
       
       audioEngine.prepare()
       try audioEngine.start()
    }
    
    public func stopRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playback)
            try audioSession.setMode(AVAudioSession.Mode.default)

        } catch {
            print("audioSession properties weren't set because of an error.")
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.inputNode.reset()
        }
    }
    
    
    // MARK: - CoreML Vision Handling
    
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
        
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            
            // 2. Loop this function.
            self.loopCoreMLUpdate()
        }
        
    }
    
    func loopSpeechRecognition() {
        
        // 1. Check if we are allowed to record speech, if yes then call startRecording()
        if(self.speechRecognition){
            dispatchQueueSpeech.async {
                try! self.startRecording()
            }
                
            dispatchQueueSpeech.asyncAfter(deadline: .now() + 65, execute: {
                self.loopSpeechRecognition()
            })
                    
        }
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        
        // Catch Errors
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }
        
        // Get Classifications
        let classifications = observations[0...1] // top 2 results
            .compactMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:"- %.2f", $0.confidence))" })
            .joined(separator: "\n")
        
        
        DispatchQueue.main.async {
            // Display Debug Text on screen
            var debugText:String = ""
            debugText += classifications
            self.debugTextView.text = debugText
            
        }
        
        if (self.spokenPhrase.contains("I can't find my wallet") || self.spokenPhrase.contains("I cannot find my wallet") || self.spokenPhrase.contains("Where's my wallet") || self.spokenPhrase.contains("Where is my wallet")){
            self.speechRecognition = false
            self.stopRecording()
            self.spokenPhrase = ""
            let utterance = AVSpeechUtterance(string: "Let me help you find your wallet.")
            utterance.rate = 0.5
            self.synthesizer.speak(utterance)
            dispatchQueueSR.async {
                let recordingsArray = self.file.retrieveRecordings()
                if (!recordingsArray.isEmpty && !self.objectList.contains("wallet recording")){
                    for recording_file in recordingsArray {
                        if(recording_file.absoluteString.contains("wallet_interaction")){
                            self.stopRecording()
                            let video = AVPlayer(url: recording_file)
                            
                            DispatchQueue.main.async {
                                let videoPlayer = AVPlayerViewController()
                                videoPlayer.player = video
                        
                                self.present(videoPlayer, animated: true, completion: {
                                    video.play()
                                })
                            }
                        }
                        break
                    }
                    self.objectList.append("wallet recording")
                    self.speechRecognition = true
                }
            }
            self.speechRecognition = true
        }
        
        // Store the latest prediction
        var objectName:String = "…"
        objectName = classifications.components(separatedBy: "-")[0]
        objectName = objectName.components(separatedBy: ",")[0]
        self.latestPrediction = objectName
        
        if(self.latestPrediction.contains("pill bottle")){
            self.latestPrediction = String(objectName.dropLast())
        }
        
        if(self.latestPrediction == "pill bottle")
        {
            if(!self.objectList.contains("pill bottle"))
            {
                self.objectList.append("pill bottle")
                self.speechRecognition = false
                self.stopRecording()
                var utterance = AVSpeechUtterance(string: "I have detected a pill bottle, I will now label this item for you to see")
                
                if self.advilFlag {
                    utterance = AVSpeechUtterance(string: "I have detected an Advil bottle, I will now label this item for you to see")
                }else if self.tylenolFlag {
                    utterance = AVSpeechUtterance(string: "I have detected a Tylenol bottle, I will now label this item for you to see. Please do not take your dosage just yet. My records indicate that you are required to take Tylenol again in 35 minutes")
                }
                
                utterance.rate = 0.5

                self.synthesizer.speak(utterance)
                let number = Int.random(in: 0 ... 10000000000)
                let recordingFile = "pill_bottle_interaction\(number)"
            
                dispatchQueueSR.async {
                    self.screenRecorder.startRecording(fileName: recordingFile)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: {
                    print("displaying pill bottle text in AR")
                    if (self.tylenolFlag){
                        self.displayARText("Tylenol Bottle")
                    } else if (self.advilFlag){
                        self.displayARText("Advil Bottle")
                    } else{
                        self.displayARText("Pill Bottle")
                    }
                })
                
                dispatchQueueSR.asyncAfter(deadline: .now() + 16.0, execute: {
                    self.screenRecorder.stopRecording()
                    self.screenRecorder.recordFlag = false
                    print("stopped recording")
                    self.recordingFinished = true
                    self.speechRecognition = true
                })
                
            }
            
                dispatchQueueSR.async {
                    
                    if (self.recordingFinished){
                        let recordingsArray = self.file.retrieveRecordings()
                        if (!recordingsArray.isEmpty && !self.objectList.contains("pill bottle recording")){
                            for recording_file in recordingsArray {
                                if(recording_file.absoluteString.contains("pill_bottle_interaction")){
                                    self.stopRecording()
                                    let speech = AVSpeechUtterance(string: "Before you proceed, let's make sure you haven't already taken your medication.")
                                    speech.rate = 0.5
                                    self.synthesizer.speak(speech)
                                    
                                    let video = AVPlayer(url: recording_file)
                                    
                                    DispatchQueue.main.async {
                                        let videoPlayer = AVPlayerViewController()
                                        videoPlayer.player = video
                                
                                        self.present(videoPlayer, animated: true, completion: {
                                            video.play()
                                        })
                                    }
                                }
                                break
                            }
                            self.objectList.append("pill bottle recording")
                            self.speechRecognition = true
                        }
                }
            }
        } else if (self.latestPrediction == "wallet"){
            if(!self.objectList.contains("wallet")){
                self.objectList.append("wallet")
                self.speechRecognition = false
                self.stopRecording()
                let utterance = AVSpeechUtterance(string: "I see you're handling your wallet. Let's record this so you don't forget where you're leaving it")
                utterance.rate = 0.5
                self.synthesizer.speak(utterance)
                let number = Int.random(in: 0 ... 10000000000)
                let recordingFile = "wallet_interaction\(number)"
            
                self.dispatchQueueSR.async {
                    self.screenRecorder.startRecording(fileName: recordingFile)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: {
                    //print("displaying pill bottle text in AR")
                    self.displayARText("wallet")
                    
                })
                
                self.dispatchQueueSR.asyncAfter(deadline: .now() + 16.0, execute: {
                    self.screenRecorder.stopRecording()
                    self.screenRecorder.recordFlag = false
                    print("stopped recording")
                    self.recordingFinished = true
                    self.speechRecognition = true
                })
                
            }
        }
    }
        
    func updateCoreML() {
        // Get Camera Image as RGB
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        // Note: Not entirely sure if the ciImage is being interpreted as RGB, but for now it works with the Inception model.
        // Note2: Also uncertain if the pixelBuffer should be rotated before handing off to Vision (VNImageRequestHandler) - regardless, for now, it still works well with the Inception model.
        
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        // let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage!, orientation: myOrientation, options: [:]) // Alternatively; we can convert the above to an RGB CGImage and use that. Also UIInterfaceOrientation can inform orientation values.
        
        let textRequestHandler = VNImageRequestHandler(ciImage: ciImage, orientation: textOrientation, options: [:])
        
        do {
            try textRequestHandler.perform([request])
        } catch {
            print(error)
        }
        
        // Run Image Request
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
        
    }
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
         
        } else {
            
        }
    }
}

extension UIFont {
    // Based on: https://stackoverflow.com/questions/4713236/how-do-i-set-bold-and-italic-on-uilabel-of-iphone-ipad
    func withTraits(traits:UIFontDescriptor.SymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptor.SymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromCATextLayerAlignmentMode(_ input: CATextLayerAlignmentMode) -> String {
    return input.rawValue
}
