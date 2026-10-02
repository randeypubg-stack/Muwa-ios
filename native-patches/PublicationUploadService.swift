import Foundation
import UniformTypeIdentifiers
import CryptoKit

struct PublicationSubmissionReceipt: Sendable {
  let audioStorageKey: String
  let coverStorageKey: String?
  let submissionStorageKey: String
}

actor PublicationUploadService {
  static let shared = PublicationUploadService()

  private struct UploadRequest: Codable {
    let draftId: String
    let part: String
    let originalName: String
    let contentType: String
    let sizeBytes: Int
    let sha256: String
  }

  private struct UploadResponse: Codable {
    let storageKey: String
    let presignedUrl: String
    let headers: [String: String]?
    let alreadyUploaded: Bool?
  }

  private struct APIError: Codable {
    let error: String
    let code: String?
  }

  private struct Envelope<T: Codable>: Codable {
    let json: T
  }

  private struct SubmissionDocument: Codable {
    let id: UUID
    let title: String
    let artist: String
    let language: String
    let audioStorageKey: String
    let coverStorageKey: String?
    let submittedAt: Date
    let client: String
  }

  func submit(
    id: UUID,
    title: String,
    artist: String,
    language: String,
    audioURL: URL,
    coverURL: URL?
  ) async throws -> PublicationSubmissionReceipt {
    guard try await AuthService.shared.restoreSession() != nil else {
      throw NSError(
        domain: "Muwa.Publication",
        code: 401,
        userInfo: [NSLocalizedDescriptionKey: "Для отправки публикации войдите в аккаунт."]
      )
    }

    let audio = try await uploadLocalFile(audioURL, draftID: id, part: "audio")
    let cover: UploadResponse?
    if let coverURL {
      cover = try await uploadLocalFile(coverURL, draftID: id, part: "cover")
    } else {
      cover = nil
    }

    // Keep the final marker byte-identical on a retry, including after relaunch.
    let dateKey = "muwa.publication.submissionDate.\(id.uuidString.lowercased())"
    let submittedAt: Date
    if let stored = UserDefaults.standard.object(forKey: dateKey) as? Date { submittedAt = stored }
    else { submittedAt = .now; UserDefaults.standard.set(submittedAt, forKey: dateKey) }
    let document = SubmissionDocument(
      id: id,
      title: title,
      artist: artist,
      language: language,
      audioStorageKey: audio.storageKey,
      coverStorageKey: cover?.storageKey,
      submittedAt: submittedAt,
      client: "Muwa Native SwiftUI"
    )
    let metadata = try JSONEncoder.iso8601.encode(document)
    let metaUpload = try await prepareUpload(
      draftID: id,
      part: "submission",
      originalName: "submission.json",
      contentType: "application/json",
      sizeBytes: metadata.count,
      sha256: SHA256.hash(data: metadata).map { String(format: "%02x", $0) }.joined()
    )
    if metaUpload.alreadyUploaded != true {
      try await put(data: metadata, to: metaUpload.presignedUrl, contentType: "application/json", headers: metaUpload.headers ?? [:])
    }

    return PublicationSubmissionReceipt(
      audioStorageKey: audio.storageKey,
      coverStorageKey: cover?.storageKey,
      submissionStorageKey: metaUpload.storageKey
    )
  }

  private func uploadLocalFile(_ fileURL: URL, draftID: UUID, part: String) async throws
    -> UploadResponse
  {
    let accessing = fileURL.startAccessingSecurityScopedResource()
    defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
    let size: Int
    if let fileSize = values.fileSize {
      size = fileSize
    } else {
      size = try Data(contentsOf: fileURL, options: .mappedIfSafe).count
    }
    guard size > 0, size <= (part == "cover" ? 10 : 100) * 1024 * 1024 else {
      throw NSError(
        domain: "Muwa.Publication", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Файл должен быть меньше 100 МБ."])
    }
    let contentType =
      values.contentType?.preferredMIMEType ?? fallbackMIME(for: fileURL, part: part)
    let upload = try await prepareUpload(
      draftID: draftID,
      part: part,
      originalName: fileURL.lastPathComponent,
      contentType: contentType,
      sizeBytes: size,
      sha256: try checksum(fileURL)
    )
    if upload.alreadyUploaded != true {
      try await put(file: fileURL, to: upload.presignedUrl, contentType: contentType, headers: upload.headers ?? [:])
    }
    return upload
  }

  private func prepareUpload(
    draftID: UUID,
    part: String,
    originalName: String,
    contentType: String,
    sizeBytes: Int,
    sha256: String
  ) async throws -> UploadResponse {
    let body = try JSONEncoder().encode(
      Envelope(
        json: UploadRequest(
          draftId: draftID.uuidString.lowercased(),
          part: part,
          originalName: originalName,
          contentType: contentType,
          sizeBytes: sizeBytes,
          sha256: sha256
        )))
    let bases = BackendConfig.candidateAPIBaseURLs
    var lastTransportError: Error?

    for (index, baseURL) in bases.enumerated() {
      var request = URLRequest(url: baseURL.appending(path: "_api/publicationUpload"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.timeoutInterval = 60
      request.httpBody = body

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await URLSession.shared.data(for: request)
      } catch {
        lastTransportError = error
        if index < bases.count - 1 { continue }
        throw error
      }

      guard let http = response as? HTTPURLResponse else {
        let error = URLError(.badServerResponse)
        if index < bases.count - 1 {
          lastTransportError = error
          continue
        }
        throw error
      }

      if BackendConfig.shouldTryFallback(statusCode: http.statusCode), index < bases.count - 1 {
        continue
      }
      guard (200..<300).contains(http.statusCode) else {
        let message: String
        if let wrapped = try? JSONDecoder().decode(Envelope<APIError>.self, from: data) {
          message = wrapped.json.error
        } else if let plain = try? JSONDecoder().decode(APIError.self, from: data) {
          message = plain.error
        } else {
          message = "Не удалось подготовить загрузку на сервер."
        }
        throw NSError(
          domain: "Muwa.Publication",
          code: http.statusCode,
          userInfo: [NSLocalizedDescriptionKey: message]
        )
      }

      if let wrapped = try? JSONDecoder().decode(Envelope<UploadResponse>.self, from: data) {
        return wrapped.json
      }
      return try JSONDecoder().decode(UploadResponse.self, from: data)
    }

    if let lastTransportError { throw lastTransportError }
    throw URLError(.badServerResponse)
  }

  private func put(file: URL, to presigned: String, contentType: String, headers: [String: String]) async throws {
    guard let url = URL(string: presigned), url.scheme == "https" else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    request.timeoutInterval = 300
    let (_, response) = try await URLSession.shared.upload(for: request, fromFile: file)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw NSError(
        domain: "Muwa.Publication", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить файл на сервер."])
    }
  }

  private func put(data: Data, to presigned: String, contentType: String, headers: [String: String]) async throws {
    guard let url = URL(string: presigned), url.scheme == "https" else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    request.timeoutInterval = 60
    let (_, response) = try await URLSession.shared.upload(for: request, from: data)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw NSError(
        domain: "Muwa.Publication", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Не удалось завершить отправку публикации."])
    }
  }

  private func checksum(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func fallbackMIME(for url: URL, part: String) -> String {
    if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
      return mime
    }
    return part == "audio" ? "audio/mpeg" : "image/jpeg"
  }
}

extension JSONEncoder {
  fileprivate static var iso8601: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    return encoder
  }
}
