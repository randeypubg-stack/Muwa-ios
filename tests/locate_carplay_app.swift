// Locate Muwa's real launcher label in an unmodified CarPlay framebuffer.
import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fatalError("Expected a native CarPlay PNG")
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
guard let label = request.results?.first(where: {
  $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "muwa"
}), let candidate = label.topCandidates(1).first, candidate.confidence >= 0.5 else {
  fatalError("Muwa was not found on the native CarPlay launcher")
}
// Vision uses a lower-left origin. Tap the icon above its label; both belong to
// the same launcher tile. No coordinates from a mockup or phone screen are used.
let x = Double(label.boundingBox.midX) * Double(image.width)
let y = (1 - Double(label.boundingBox.midY)) * Double(image.height) - Double(image.height) * 0.18
let result: [String: Any] = ["x": x, "y": max(0, y), "width": image.width,
                           "height": image.height, "label": candidate.string,
                           "confidence": candidate.confidence]
let data = try JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
print(String(decoding: data, as: UTF8.self))
