//
//  ViewController.swift
//  interspace-arkit-poc-browser
//
//  Created by Ben Woodley on 30/03/2021.
//
import ARKit
import RealityKit

struct Vector3: Codable {
    let x: Float
    let y: Float
    let z: Float
}

struct Vector4: Codable {
    let w: Float
    let x: Float
    let y: Float
    let z: Float
}

struct InterspaceAnchor: Codable {
    let id: String
    let image_url: String
    let width_cm: Float
    let height_cm: Float
    let position: Vector3
    let orientation: Vector4
    let is_setup: Bool
    let is_origin: Bool
}

class ViewController: UIViewController, ARSessionDelegate {
    @IBOutlet var arView: ARView!
    
    var imageAnchorToEntity: [ARImageAnchor: AnchorEntity] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        arView.session.delegate = self
        let config = ARWorldTrackingConfiguration()
        arView.automaticallyConfigureSession = false
        config.sceneReconstruction = .meshWithClassification
        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.session.run(config, options: [])
        
        var newReferenceImages: Set<ARReferenceImage> = Set<ARReferenceImage>()
        
        struct Response: Codable {
            let anchors: [InterspaceAnchor]
        }
        
        
        if let url = URL(string: "http://10.100.0.204:8080/anchors") {
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let data = data {
                    do {
                        let res = try JSONDecoder().decode(Response.self, from: data)
                        print(res.anchors)
                        for interspaceAnchor in res.anchors {
                            print("anchor retrieved from Interspace")
                            let url = URL(string: interspaceAnchor.image_url)!
                            if let data = try? Data(contentsOf: url) {
                                let downloadedImage = UIImage(data: data)
                                let cgImage = downloadedImage?.cgImage
                                let image = ARReferenceImage(cgImage!, orientation: CGImagePropertyOrientation.up, physicalWidth: CGFloat(interspaceAnchor.width_cm/100))
                                newReferenceImages.insert(image)
                            }
                        }
                        config.detectionImages = newReferenceImages
                        print("Session rerun")
                        self.arView.session.run(config)
                    } catch let error {
                        print(error)
                    }
                }
           }.resume()
        }
        
        config.detectionImages = newReferenceImages
        print("Session rerun")
        arView.session.run(config)
        
        // Set world origin to origin anchor's transform
        // arView.session.setWorldOrigin(relativeTransform: anchor.transform)
        
    }
    
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        anchors.compactMap { $0 as? ARImageAnchor }.forEach {
            
            let anchorEntity = AnchorEntity()
            let boxAnchor = try! Experience.loadBox()
            let modelEntity = boxAnchor.steelBox!
            anchorEntity.addChild(modelEntity)
            arView.scene.addAnchor(anchorEntity)
            anchorEntity.transform.matrix = $0.transform
            imageAnchorToEntity[$0] = anchorEntity
            // This is for the origin anchor
            //self.arView.session.setWorldOrigin(relativeTransform: anchorEntity.transform)
        }
    }
    
    func getInterspaceAnchorArray() -> [InterspaceAnchor]{
        struct Response: Codable {
            let anchors: [InterspaceAnchor]
        }
        var anchor_list: [InterspaceAnchor] = []
        
        if let url = URL(string: "http://10.100.0.204:8080/anchors") {
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let data = data {
                    do {
                        let res = try JSONDecoder().decode(Response.self, from: data)
                        //return res.anchors
                    } catch let error {
                        print(error)
                    }
                }
           }.resume()
        }
        return anchor_list
    }
    
    func create_anchor() {
        let position = Vector3(x: 0, y: 0, z: 0)
        let orientation = Vector4(w: 0, x: 0, y: 0, z: 0)
        let anchor = InterspaceAnchor(
            id: UUID().uuidString,
            image_url: "http://10.100.0.204:8080/image/anchor_03.jpg",
            width_cm: 8.0,
            height_cm: 8.0,
            position: position,
            orientation: orientation,
            is_setup: true,
            is_origin: true
        )
        guard let requestData = try? JSONEncoder().encode(anchor) else { return }
        
        let url = URL(string: "http://10.100.0.204:8080/create_anchor")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct Response: Codable {
            let status: String
        }
        
        URLSession.shared.uploadTask(with: request, from: requestData) { data, response, error in
            if let data = data {
                do {
                    let res = try JSONDecoder().decode(Response.self, from: data)
                    print(res.status)
                } catch let error {
                    print(error)
                }
            }
        }.resume()
    }
}
