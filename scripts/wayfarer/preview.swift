// macOS SceneKit geometry preview only; not an App/RealityKit screenshot.
import AppKit
import SceneKit
let scene = try SCNScene(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.zNear = 0.001; camera.camera!.zFar = 10; camera.position = SCNVector3(0,0,0.32)
scene.rootNode.addChildNode(camera)
scene.background.contents = NSColor(red:0.86,green:0.78,blue:0.89,alpha:1)
let content = scene.rootNode.childNodes.filter { $0 !== camera }
for node in content { node.eulerAngles = SCNVector3(0.25,-0.5,0) }
let light = SCNNode(); light.light = SCNLight(); light.light!.type = .directional; light.light!.intensity = 800; light.position = SCNVector3(0.1,0.2,0.3); scene.rootNode.addChildNode(light)
let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 200; scene.rootNode.addChildNode(ambient)
let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = scene; renderer.pointOfView = camera
let image = renderer.snapshot(atTime:0,with:CGSize(width:900,height:700),antialiasingMode:.multisampling4X)
let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/wayfarer-model.png"))
