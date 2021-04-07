//
//  ViewControllerNew.swift
//  interspace-arkit-poc-browser
//
//  Created by Ben Woodley on 02/04/2021.
//

import ARKit
import RealityKit

// For decoding JSON text storing position
struct Vec3: Codable {
    let x: Float
    let y: Float
    let z: Float
}
// For decoding JSON text storing orientation
struct Vec4: Codable {
    let w: Float
    let x: Float
    let y: Float
    let z: Float
}

// For decoding JSON text storing an anchor
struct Anchor: Codable {
    let id: String
    let image_filename: String
    let width_cm: Float
    let height_cm: Float
    let position: Vec3
    let orientation: Vec4
    let is_setup: Bool
    let is_origin: Bool
}

// class reponsible for all app functionality thus far
class ViewController: UIViewController, ARSessionDelegate {
    
    // the object that is/manages the view for a RealityKit appe
    @IBOutlet var arView: ARView!
    
    // the object for configuring how the the ARSession operates
    var arConfig = ARWorldTrackingConfiguration()
    
    // dictionary to associate each ARImageAnchor (ARKit) with a AnchorEntity (RealityKit)
    var imageAnchorToEntity: [ARImageAnchor: AnchorEntity] = [:]
    
    // the object that deals with downloading web data
    let session = URLSession.shared
    
    // create a URL object with the base url where interspace-python-poc-server can be reached
    let baseUrl = URL(string: "http://10.100.0.204:8080")!
    
    // the array of interspace anchors
    var loaded_anchors: [Anchor] = []
    
    // the interspace anchor which is setup to be the world 0, 0, 0
    var origin_anchor: Anchor? = nil
    
    // ask the Interspace for a list of anchors
    func requestAnchors(baseUrl: URL) {
        // create a URL object (using the base url of the Interspace with the path to get the anchor list)
        let url = URL(string: "/anchors", relativeTo: baseUrl)!
        // create a task which queries the url with a GET request, calling 'receiveAnchors' when it gets a reply
        let task = session.dataTask(with: url, completionHandler: recieveAnchors)
        // start the task (doesn't run in the main thread)
        task.resume()
    }
    
    // called by the task that was setup in the 'requestAnchors' function with GET request's reply
    func recieveAnchors(data: Data?, response: URLResponse?, error: Error?) {
        // create a struct for decoding the JSON data of the reply
        struct DecodedData: Codable {
            let anchors: [Anchor]
        }
        // if the reply's 'data' variable contains anything (also making it type 'Data' not 'Data?')
        if let data = data {
            // if the JSON text in 'data' decoded into an instance of the 'DecodedData' struct
            if let decodedData = try? JSONDecoder().decode(DecodedData.self, from: data) {
                // make loading the anchors happen in the main thread (im not certain the effect of not doing this)
                DispatchQueue.main.async {
                    // call function to load the anchors for detection
                    self.loadAnchors(anchors: decodedData.anchors)
                }
            }
        }
    }
    
    // load the images of each anchor into the images for the ARSession to detect
    func loadAnchors(anchors: [Anchor]) {
        // create an empty set of ARReferenceImage(s)
        var detectionImages = Set<ARReferenceImage>()
        // for each anchor, load the image it specifes (with a url) into an ARReferenceImage
        for anchor in anchors {
            // if an ARReferenceImage object is returned from getDetectionImage
            if let detectionImage = getDetectionImage(anchor: anchor) {
                // add it to the ARReferenceImage set
                detectionImages.insert(detectionImage)
            }
        }
        // make the images for the ARSession to detect the new ARReferenceImage set
        arConfig.detectionImages = detectionImages
        // reload (somehow without stopping) the ARSession, with its new images to detect
        arView.session.run(arConfig)
        
        for anchor in anchors {
            if anchor.is_origin == true {
                origin_anchor = anchor
            }
        }
        if origin_anchor == nil {
            print("no origin anchor found on the interspace, setting origin on the first detection")
        }
        else {
            print("origin anchor loaded")
        }
        loaded_anchors = anchors
    }
    
    // load the image a passed anchor specifies (with a url) into an ARReferenceImage
    func getDetectionImage(anchor: Anchor) -> ARReferenceImage? {
        // create a URL object from the passed anchor's image url string
        let url = URL(string: "/image/" + anchor.image_filename, relativeTo: baseUrl)!
        // create an object that stores the width in meters derived from the anchor's width in cm
        let width = CGFloat(anchor.width_cm/100)
        // define the orientation for the ARReferenceImage (this isnt the anchor's 3D orientation)
        let orientation = CGImagePropertyOrientation.up
        // if data was returned after downloading it from the url
        if let data = try? Data(contentsOf: url) {
            // if the downloaded data could be used to instance a UIImage object
            if let imageObject = UIImage(data: data) {
                // load the underlying image data (Apples format)
                let image = imageObject.cgImage!
                // create an ARReferenceImage instance, for use by the ARSession for detecting the anchor
                let detectionImage = ARReferenceImage(image, orientation: orientation, physicalWidth: width)
                // define the name for the ARReferenceImage to identify which anchor it belongs to
                detectionImage.name = anchor.id
                // return the ARReferenceImage instance
                return detectionImage
            }
        }
        // return empty if something failed getting the detectionImage
        return nil
    }
    
    // called when the view loads, this is where execution for us begins
    override func viewDidLoad() {
        // make sure what ever was using viewDidLoad before still can do its thing first
        super.viewDidLoad()
        // make the ViewController class where RealityKit/ARSession events end up
        arView.session.delegate = self
        // tell RealityKit not to configure the ARSession for us (full effect uncertain)
        arView.automaticallyConfigureSession = false
        // tell RealityKit to create a mesh while the ARSession runs using the LiDAR sensor
        arConfig.sceneReconstruction = .meshWithClassification
        // tell RealityKit to draw that mesh as a colourful wireframe over everything it sees
        arView.debugOptions.insert(.showSceneUnderstanding)
        // tell RealityKit to start the ARSession with the config so far
        arView.session.run(arConfig)
        // request the anchors from it (this will run a chain of functions, mostly out of the main thread)
        requestAnchors(baseUrl: baseUrl)
    }
    
    // function called whenever an ARAnchor is added (including when images are detected)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // for each ARAnchor that is an ARImageAnchor (a detected image)
        anchors.compactMap { $0 as? ARImageAnchor }.forEach {
            for anchor in loaded_anchors {
                if anchor.id == $0.referenceImage.name {
                    if origin_anchor == nil {
                        print("initial anchor found, making it the origin")
                        let url = URL(string: "/set_origin_anchor/" + anchor.id, relativeTo: baseUrl)!
                        if let status = try? String(contentsOf: url) {
                            print(status)
                            
                        }
                        
                    }
                    else {
                        print("origin anchor is present")
                    }
                }
            }
            
            // create a RealityKit AnchorEntity instance
            let anchorEntity = AnchorEntity()
            // load an instance of a 'Box' from RealityKit, defined in the Experience.rcproject
            let boxAnchor = try! Experience.loadBox()
            // load an instance of the model entity from the 'Box'
            let modelEntity = boxAnchor.steelBox!
            // parent the model entity to the AnchorEntity instance
            anchorEntity.addChild(modelEntity)
            // add the AnchorEntity instance to the RealityKit scene
            arView.scene.addAnchor(anchorEntity)
            // set the AnchorEntity instances position & orientation to the ARImageAnchors
            anchorEntity.transform.matrix = $0.transform
            // add the AnchorEntity instance against the ARImageAnchor in the dictionary
            imageAnchorToEntity[$0] = anchorEntity
        }
    }
}

