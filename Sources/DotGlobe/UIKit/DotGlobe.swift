//
//  File.swift
//
//
//  Created by Demirhan Mehmet Atabey on 25.05.2023.
//

import Foundation
import SceneKit
import CoreImage

public class GlobeViewController: UIViewController {
    public var earthNode: SCNNode!
    private var sceneView : SCNView!
    private var cameraNode: SCNNode!
    private var worldMapImage : CGImage {
        guard let path = Bundle.module.path(forResource: "earth-dark", ofType: "jpg") else { fatalError("Could not locate world map image.") }
        guard let image = UIImage(contentsOfFile: path)?.cgImage else { fatalError() }
        return image
    }

    private lazy var imgData: CFData = {
        guard let imgData = worldMapImage.dataProvider?.data else { fatalError("Could not fetch data from world map image.") }
        return imgData
    }()

    private lazy var worldMapWidth: Int = {
        return worldMapImage.width
    }()

    public var earthRadius: Double = 1.0 {
        didSet {
            if let earthNode = earthNode {
                earthNode.removeFromParentNode()
                setupGlobe()
            }
        }
    }
   
    
    public var dotSize: CGFloat = 0.005 {
        didSet {
            if dotSize != oldValue {
                setupDotGeometry()
            }
        }
    }
    
    public var enablesParticles: Bool = true {
        didSet {
            if enablesParticles {
                setupParticles()
            } else {
                sceneView.scene?.rootNode.removeAllParticleSystems()
            }
        }
    }
    
    public var particles: SCNParticleSystem? {
        didSet {
            if let particles = particles {
                sceneView.scene?.rootNode.removeAllParticleSystems()
                sceneView.scene?.rootNode.addParticleSystem(particles)
            }
        }
    }
    
    public var background: UIColor? {
        didSet {
            if let background = background {
                view.backgroundColor = background
            }
        }
    }
    
    public var earthColor: UIColor = .earthColor {
        didSet {
            if let earthNode = earthNode {
                earthNode.geometry?.firstMaterial?.diffuse.contents = earthColor
            }
        }
    }
    
    public var glowColor: UIColor = .earthGlow {
        didSet {
            if let earthNode = earthNode {
                earthNode.geometry?.firstMaterial?.emission.contents = glowColor
            }
        }
    }
    
    public var reflectionColor: UIColor = .earthReflection {
        didSet {
            if let earthNode = earthNode {
                earthNode.geometry?.firstMaterial?.emission.contents = glowColor
            }
        }
    }

    public var glowShininess: CGFloat = 1.0 {
        didSet {
            if let earthNode = earthNode {
                earthNode.geometry?.firstMaterial?.shininess = glowShininess
            }
        }
    }

    private var dotRadius: CGFloat {
        if dotSize > 0 {
             return dotSize
        }
        else {
            return 0.01 * CGFloat(earthRadius) / 1.0
        }
    }

    private var dotCount = 12500
    
    public init(earthRadius: Double) {
        self.earthRadius = earthRadius
        super.init(nibName: nil, bundle: nil)
    }
    
    public init(earthRadius: Double, dotCount: Int) {
        self.earthRadius = earthRadius
        self.dotCount = dotCount
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        if enablesParticles {
            setupParticles()
        }
        setupCamera()
        setupGlobe()
        setupDotGeometry()
        if let background = background {
            setupBackground(color: background)
        }
    }
    
    private func setupScene() {
        let scene = SCNScene()
        sceneView = SCNView(frame: view.frame)

        sceneView.scene = scene
        
        sceneView.showsStatistics = true
        sceneView.backgroundColor = .black
        sceneView.allowsCameraControl = true
        
        self.view.addSubview(sceneView)
    }
    
    private func setupParticles() {
        guard let stars = SCNParticleSystem(named: "StarsParticles.scnp", inDirectory: nil) else { return }
        stars.isLightingEnabled = false
        sceneView.scene?.rootNode.addParticleSystem(stars)
    }
    
    private func setupBackground(color: UIColor) {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = view.bounds
        gradientLayer.colors = [color.cgColor, UIColor.black.cgColor]
        view.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    private func setupCamera() {
        self.cameraNode = SCNNode()
        
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)

        
        sceneView.scene?.rootNode.addChildNode(cameraNode)
    }
    
    private func setupGlobe() {
        self.earthNode = EarthNode(radius: earthRadius, earthColor: earthColor, earthGlow: glowColor, earthReflection: reflectionColor)
        sceneView.scene?.rootNode.addChildNode(earthNode)
    }
    
    private func setupDotGeometry() {
        self.generateTextureMap(radius: CGFloat(earthRadius)) { textureMap in
            printTimeElapsedWhenRunningCode(title: "setuppingDotGeometry") {
                let dotColor = UIColor(white: 1, alpha: 1)

                // threshold to determine if the pixel in the earth-dark.jpg represents terrain (0.03 represents rgb(7.65,7.65,7.65), which is almost black)
                let threshold: CGFloat = 0.03

                let dotGeometry = SCNSphere(radius: dotRadius)

                dotGeometry.firstMaterial?.diffuse.contents = dotColor
                dotGeometry.firstMaterial?.lightingModel = SCNMaterial.LightingModel.constant

                var positions = [SCNVector3]()
                var dotNodes = [SCNNode]()

                printTimeElapsedWhenRunningCode(title: "setuppingDotGeometry: preparing positions") {
                    for i in 0...textureMap.count - 1 {
                        let u = textureMap[i].x
                        let v = textureMap[i].y

                        let pixelColor = self.getPixelColor(x: Int(u), y: Int(v))

                        if pixelColor.red < threshold && pixelColor.green < threshold && pixelColor.blue < threshold {
                            let dotNode = SCNNode(geometry: dotGeometry)
                            dotNode.position = textureMap[i].position
                            positions.append(dotNode.position)
                            dotNodes.append(dotNode)
                        }
                    }
                }

                DispatchQueue.main.async {
                    printTimeElapsedWhenRunningCode(title: "setuppingDotGeometry: constructing vectors") {
                        let dotPositions = positions as NSArray
                        let dotIndices = NSArray()
                        let source = SCNGeometrySource(vertices: dotPositions as! [SCNVector3])
                        let element = SCNGeometryElement(indices: dotIndices as! [Int32], primitiveType: .point)

                        let pointCloud = SCNGeometry(sources: [source], elements: [element])

                        let pointCloudNode = SCNNode(geometry: pointCloud)
                        for dotNode in dotNodes {
                            pointCloudNode.addChildNode(dotNode)
                        }

                        self.sceneView.scene?.rootNode.addChildNode(pointCloudNode)
                    }
                }
                
                self.sceneView.scene?.rootNode.addChildNode(pointCloudNode)
            }
        }
    }

    private func generateTextureMap(radius: CGFloat, completion: ([(position: SCNVector3, x: Int, y: Int)]) -> ()) {
        printTimeElapsedWhenRunningCode(title: "generateTextureMap") {
            var textureMap = [(position: SCNVector3, x: Int, y: Int)]()
            printTimeElapsedWhenRunningCode(title: "reserveCapacity") {
                textureMap.reserveCapacity(dotCount)
            }
            let doubleDotCount = Double(dotCount)
            let floatWorldMapImageHeight = CGFloat(worldMapImage.height)
            let floatWorldMapImageWidth = CGFloat(worldMapImage.width)
            for i in 0...dotCount {
                let phi = acos(-1 + (2 * Double(i)) / doubleDotCount)
                let theta = sqrt(doubleDotCount * Double.pi) * phi

                let x = sin(phi) * cos(theta)
                let y = sin(phi) * sin(theta)
                let z = cos(phi)

                let u = CGFloat(theta) / (2 * CGFloat.pi)
                let v = CGFloat(phi) / CGFloat.pi

                if u.isNaN || v.isNaN {
                    return
                }

                let xPixel = Int(u * floatWorldMapImageWidth)
                let yPixel = Int(v * floatWorldMapImageHeight)

                textureMap.append((position: SCNVector3(x: Float(x) * Float(radius), y: Float(y) * Float(radius), z: Float(z) * Float(radius)), x: xPixel, y: yPixel))
            }
            completion(textureMap)
        }
    }

    private func getPixelColor(x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(imgData)
        let pixelInfo: Int = ((worldMapWidth * y) + x) * 4

        let r = CGFloat(data[pixelInfo]) / CGFloat(255.0)
        let g = CGFloat(data[pixelInfo + 1]) / CGFloat(255.0)
        let b = CGFloat(data[pixelInfo + 2]) / CGFloat(255.0)
        let a = CGFloat(data[pixelInfo + 3]) / CGFloat(255.0)

        return (r, g, b, a)
    }
}

private extension UIColor {
    static var earthColor: UIColor {
        return UIColor(red: 0.227, green: 0.133, blue: 0.541, alpha: 1.0)
    }
    
    static var earthGlow: UIColor {
        UIColor(red: 0.133, green: 0.0, blue: 0.22, alpha: 1.0)
    }
    
    static var earthReflection: UIColor {
        UIColor(red: 0.227, green: 0.133, blue: 0.541, alpha: 1.0)
    }
}