// Verify a real Simulator framebuffer while the account service is still held.
import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fatalError("Expected a native Home PNG")
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["ru-RU", "en-US"]
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
let text = lines.joined(separator: " ").lowercased()
guard text.contains("главная"), text.contains("нашиды"),
      !text.contains("открываем muwa"), !text.contains("войти или создать аккаунт") else {
  fatalError("Home was not visible while the account service was pending: \(lines)")
}
let proof: [String: Any] = ["homeVisible": true, "width": image.width, "height": image.height, "lines": lines]
let data = try JSONSerialization.data(withJSONObject: proof, options: .sortedKeys)
print(String(decoding: data, as: UTF8.self))
