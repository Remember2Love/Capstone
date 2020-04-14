import Foundation
import ARKit
import Vision

struct Contact: Codable {
    var name: String
    var relationship: String
    var description: String
}

//used when creating the card and displaying the contact data
struct Values {
    static let cardSize: Float = 2.5
    static let cardWidth: CGFloat = CGFloat(0.125 * cardSize)
    static let cardHeight: CGFloat = CGFloat(0.075 * cardSize)
    
    static let horizontalOffset: Float = 0.0 * cardSize
    static let verticalOffset: Float = 0.0775 * cardSize
    
    static let lineSpacing: Float = 0.02 * cardSize
    static let scaleName: Float = 0.004 * cardSize
    static let scaleTitle: Float = 0.004 * cardSize
    static let scaleDescription: Float = 0.004 * cardSize
}

final class ViewModel {
    
    private let state: StateOfAR
    
    private var currentBuffer: CVPixelBuffer?
    private let visionQueue = DispatchQueue(label: "visionQueue")
    
    var contacts: [Contact]?
    var contact: Contact?
    
    var sceneView: ARSCNView?
    var bounds: CGRect?
    var cardDictionary = [String : SCNNode]()
    var planeNode: SCNNode?
    
    var currentNode: SCNNode? {
        get {
            return self.state.node
        }
        set {
            self.state.node?.removeFromParentNode()
            self.state.node = newValue
        }
    }
    
    var stateChangeHandler: ((StateOfAR.Change) -> Void)? {
        get { return state.onChange }
        set { state.onChange = newValue }
    }
    
    private var imageOrientation: CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        default: return .right
        }
    }
    
    init(sceneView: ARSCNView) {
        self.state = StateOfAR()
        self.sceneView = sceneView
        self.bounds = sceneView.bounds
    }

    //grab image in current view
    func takeCapturedImage(from frame: ARFrame) {
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        
        self.currentBuffer = frame.capturedImage
        classifyCurrentImage()
    }
    
    //take the captured image and request a VNImageRequestHandler which calls the classificationRequest function
    private func classifyCurrentImage() {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: imageOrientation)
        visionQueue.async {
            do {
                defer { self.currentBuffer = nil }
                try requestHandler.perform([self.classificationRequest])
            } catch {
                print("image request error")
            }
        }
    }
    
    //use the set coreML model (currently Faces_Redone) to classify the given image
    private lazy var classificationRequest: VNDetectFaceRectanglesRequest = {
        do {
            //coreML model set
            let model = try VNCoreMLModel(for: FaceRecognitionFinal3().model)
            
            //detect the face
            let detectFaceRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in
                //if a result shows up, therefore a face is in the image, perform the coreML request and process the classification
                if let face = request.results?.first as? VNFaceObservation {
                    let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] (request, error) in
                        self?.processClassification(for: request, error: error)
                    })
                    
                    //crop the center of the image
                    request.imageCropAndScaleOption = .centerCrop
                    request.usesCPUOnly = true
                    
                    let handler = VNImageRequestHandler(cvPixelBuffer: self.currentBuffer!, options: [:])
                    try? handler.perform([request])
                    
                    let boundingBox = self.transformBoundingBox(face.boundingBox)
                    guard let worldCoordination = self.normalizeWorldCoord(boundingBox),
                        let contactName = self.contact?.name else { return }
                     guard let _ = self.cardDictionary[contactName] else {
                        DispatchQueue.main.async{
                            self.currentNode = self.createCard(facePosition: worldCoordination, contact: self.contact)
                        }
                        return
                    }
                }
                //if no face is found
                else {
                    self.cardDictionary = [:]
                }
            })
            return detectFaceRequest
        } catch  {
            fatalError("Failed to load  ML model: \(error)")
        }
    }()
    
    //performs the VNRequest
    func processClassification (for request: VNRequest, error: Error?){
        guard let results = request.results else {
            print("Unable to classify image.\n\(error!.localizedDescription)")
            return
        }
        
        let classifications = results as! [VNClassificationObservation]
        
        //takes the highest confidence result if it has a higher than 0.8 confidence, decodes the Contacts.json file with the infoGetter class, and finds the correct contact that the image was classified as
        if let bestResult = classifications.first(where: { result in result.confidence > 0.80}) {
            self.contacts = loadJson("Contacts")!
            self.contacts?.forEach({ (contact) in
                if contact.name == bestResult.identifier {
                    self.contact = contact
                }
            })
        }
    }
    
    func loadJson(_ fileName: String) -> [Contact]? {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                
                let jsonData = try decoder.decode([Contact].self, from: data)
                return jsonData
            } catch {
                print("error:\(error)")
            }
        }
        return nil
    }
    
    //CREATION OF CARD NEAR FACE
    
    //creation of the card / background
    func createCard(facePosition: SCNVector3, contact: Contact?) -> SCNNode? {
        
        //contact values added to approriate variables, if none then nil
        guard let name = contact?.name else { return nil }
        guard let title = contact?.relationship else { return nil }
        guard let description = contact?.description else { return nil }
        
        
        if let card = cardDictionary[name] {
            offsetPositionCard(card, facePosition)
            return card
        }
        let card = createPlane()
        
        //text nodes created to display on card with proper text scaling assigned
        let contactName = createTextNode(string: "Name: \(name)", scale: Values.scaleName)
        let contactTitle = createTextNode(string: "Relationship: \(title)", scale: Values.scaleTitle)
        let contactDescription = createTextNode(string: "Last Interacted With: \(description)", scale: Values.scaleDescription)
        
        //text nodes then positioned onto the created card
        positionText(textNode: contactName, card: card, verticalPlacement: 1.0)
        positionText(textNode: contactTitle, card: card, verticalPlacement: 2.0)
        positionText(textNode: contactDescription, card: card, verticalPlacement: 3.0)
        
        //card offset added to not cover the face
        offsetPositionCard(card, facePosition)
        
        //card added to card dictionary
        cardDictionary[name] = card
        
        //keeps the created card flat side towards the user for easier reading
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        card.constraints = [billboardConstraint]
        
        return card
    }
    
    //receives position as a 3D Scene Vector, then offsets this position vertical and horizontal offsets
    func offsetPositionCard(_ card: SCNNode, _ position: SCNVector3) {
        card.position = position
        card.position.y += Values.verticalOffset
        card.position.x += Values.horizontalOffset
    }
    
    //plane created to add the card to
    func createPlane() -> SCNNode {
        let plane = SCNPlane(width: Values.cardWidth, height: Values.cardHeight)
        let cardBackground = SCNMaterial()
        
        //background set to our logo
        cardBackground.diffuse.contents = "Remember2LoveBackground.png"
        plane.firstMaterial = cardBackground
        plane.cornerRadius = 0.001
        
        self.planeNode = SCNNode(geometry: plane)
        return planeNode!
    }

    //text for displaying each type of information about the contact
    func createTextNode(string: String, scale: Float) -> SCNNode {
        let textGeo = SCNText(string: string, extrusionDepth: 0.1)
        textGeo.flatness = 0.3
        textGeo.font = UIFont(name: "Georgia", size: 1.5)
        textGeo.firstMaterial!.diffuse.contents = UIColor.blue
        
        let textNode = SCNNode(geometry: textGeo)
        textNode.scale = SCNVector3(scale, scale, scale)
        return textNode
    }
    
    //positioning of each text node
    func positionText(textNode: SCNNode, card: SCNNode, verticalPlacement: Float) {
        let (card_box_min, card_box_max) = card.boundingBox
        let (text_box_min, text_box_max) = textNode.boundingBox
        
        textNode.position = card.position
        textNode.position.x = card_box_min.x + ((card_box_max.x - card_box_min.x) - ((text_box_max.x - text_box_min.x) * Values.scaleName)) / 2
        textNode.position.y = card_box_max.y - verticalPlacement * Values.lineSpacing
        
        card.addChildNode(textNode)
    }
    
    //function to normalize world coordinates for the SCNVector3 class (found online)
    private func normalizeWorldCoord(_ boundingBox: CGRect) -> SCNVector3? {
        
        var array: [SCNVector3] = []
        Array(0...2).forEach{_ in
            if let position = determineWorldCoord(boundingBox) {
                array.append(position)
            }
            usleep(12000)
        }
        
        if array.isEmpty {
            return nil
        }
        
        return SCNVector3.center(array)
    }
    
    //function to normalize world coordinates for the SCNVector3 class (found online)
    private func determineWorldCoord(_ boundingBox: CGRect) -> SCNVector3? {
        let arHitTestResults = sceneView?.hitTest(CGPoint(x: boundingBox.midX, y: boundingBox.midY), types: [.featurePoint])
        
        if let closestResult = arHitTestResults?.filter({ $0.distance > 0.10 }).first {
            return SCNVector3.positionFromTransform(closestResult.worldTransform)
        }
        return nil
    }

    //adjust bounding box depending on orientation of the phone 
    private func transformBoundingBox(_ boundingBox: CGRect) -> CGRect {
        var size: CGSize
        var origin: CGPoint
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight:
            size = CGSize(width: boundingBox.width * (bounds?.height)!,
                          height: boundingBox.height * (bounds?.width)!)
        default:
            size = CGSize(width: boundingBox.width * (bounds?.width)!,
                          height: boundingBox.height * (bounds?.height)!)
        }
        
        
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            origin = CGPoint(x: boundingBox.minY * (bounds?.width)!,
                             y: boundingBox.minX * (bounds?.height)!)
        case .landscapeRight:
            origin = CGPoint(x: (1 - boundingBox.maxY) * (bounds?.width)!,
                             y: (1 - boundingBox.maxX) * (bounds?.height)!)
        case .portraitUpsideDown:
            origin = CGPoint(x: (1 - boundingBox.maxX) * (bounds?.width)!,
                             y: boundingBox.minY * (bounds?.height)!)
        default:
            origin = CGPoint(x: boundingBox.minX * (bounds?.width)!,
                             y: (1 - boundingBox.maxY) * (bounds?.height)!)
        }
        return CGRect(origin: origin, size: size)
    }
    
}


