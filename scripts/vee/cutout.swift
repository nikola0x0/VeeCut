// Lifts Vee off the flat background with Vision and scales it to the bundled poses' 420 px height.
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
let handler = VNImageRequestHandler(url: URL(fileURLWithPath: args[1]))
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let observation = request.results?.first else { fatalError("no foreground") }
let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
var image = CIImage(cvPixelBuffer: buffer)
let scale = 420 / image.extent.height
image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let context = CIContext()
try context.writePNGRepresentation(of: image, to: URL(fileURLWithPath: args[2]), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
