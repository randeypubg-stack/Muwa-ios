// Verify a real Simulator framebuffer while the account service is still held.
import Foundation
import CoreML
import Darwin
import ImageIO
import Vision

func verificationError(_ message: String) -> NSError {
  NSError(domain: "MuwaHomeVerification", code: 1,
          userInfo: [NSLocalizedDescriptionKey: message])
}

do {
  guard CommandLine.arguments.count == 2,
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    throw verificationError("Expected a native Home PNG")
  }
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.recognitionLanguages = ["ru-RU", "en-US"]
  request.usesLanguageCorrection = false
  // Hosted macOS may have no usable GPU/ANE for Vision. Select an advertised
  // CPU device for every stage rather than relying on the graphics driver.
  if #available(macOS 14.0, *) {
    let supported = try request.supportedComputeStageDevices
    guard !supported.isEmpty else {
      throw verificationError("Vision did not advertise any OCR compute stages")
    }
    for (stage, devices) in supported {
      guard let cpu = devices.first(where: {
        if case .cpu = $0 { return true }
        return false
      }) else {
        throw verificationError("Vision has no CPU device for OCR stage \(stage)")
      }
      request.setComputeDevice(cpu, for: stage)
    }
  } else {
    request.usesCPUOnly = true
  }
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
  let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
  let text = lines.joined(separator: " ").lowercased()
  guard text.contains("главная"), text.contains("нашиды"),
        !text.contains("открываем muwa"), !text.contains("войти или создать аккаунт") else {
    throw verificationError("Home was not visible while the account service was pending: \(lines)")
  }
  let proof: [String: Any] = ["homeVisible": true, "width": image.width,
                            "height": image.height, "lines": lines,
                            "recognitionEngine": "Vision", "computeDevice": "cpu"]
  let data = try JSONSerialization.data(withJSONObject: proof, options: .sortedKeys)
  print(String(decoding: data, as: UTF8.self))
} catch {
  // A top-level throw traps and can bury the first NSError under a Swift/JIT
  // crash dump. Preserve the real Vision failure and exit without a trap.
  let error = error as NSError
  let failure: [String: Any] = ["homeVisible": false, "errorDomain": error.domain,
                              "errorCode": error.code,
                              "errorMessage": error.localizedDescription]
  if let data = try? JSONSerialization.data(withJSONObject: failure, options: .sortedKeys) {
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
  } else {
    FileHandle.standardError.write(Data("Home verification failed: \(error)\n".utf8))
  }
  exit(EXIT_FAILURE)
}
