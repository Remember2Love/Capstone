import UIKit
import SceneKit
import ARKit
import Vision

class ViewController: UIViewController {

    @IBOutlet weak var sceneView: ARSCNView!
    
    private var viewModel: ViewModel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.session.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        sceneView.autoenablesDefaultLighting = true
        
        viewModel = ViewModel(sceneView: sceneView)
        
        //change state of AR
        viewModel.stateChangeHandler = { [weak self] change in self?.applyStateChange(change)}
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    func applyStateChange(_ change: StateOfAR.Change) {
        DispatchQueue.main.async {
            switch change {
            case let .node(node):
                guard let node = node else {
                    return
                }
                self.sceneView.scene.rootNode.addChildNode(node)
            }
        }
    }
}

extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        viewModel.takeCapturedImage(from: frame)
    }
}
