import ARKit

//changes state to void or gives a scene node, class found online
final class StateOfAR {
    
    enum Change {
        case node(SCNNode?)
    }
    
    var onChange: ((StateOfAR.Change) -> Void)?
    
    var node: SCNNode? {
        
        didSet{ onChange?(.node(node))}
        
    }
}
