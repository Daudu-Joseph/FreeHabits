import Foundation
import SwiftUI
import Combine
import CryptoKit

struct NVIDIAAvailableModel: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case listed, available, denied, unsupported, retry }
    let id: String
    var status: Status = .listed
    var checkedAt: Date?
    var detail: String?
}

@MainActor
final class NVIDIAModelCatalog: ObservableObject {
    @Published private(set) var models: [NVIDIAAvailableModel] = []
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var checking = false
    @Published private(set) var progress = ""
    @Published private(set) var message: String?
    private var fingerprint: String?
    private let cacheName = "nvidiaModelCatalog.v1"
    private struct Cache: Codable {
        let keyFingerprint: String
        let fetchedAt: Date
        let models: [NVIDIAAvailableModel]
    }
    var usable: [String] { models.filter { $0.status == .available }.map(\.id).sorted() }
    private func identity(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func load() {
        guard let key = AssistantKeychain.read() else { clear(); return }
        let id = identity(key)
        fingerprint = id
        guard let data = UserDefaults.standard.data(forKey: cacheName),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.keyFingerprint == id else {
            models = []; fetchedAt = nil
            UserDefaults.standard.removeObject(forKey: cacheName)
            return
        }
        models = cache.models
        fetchedAt = cache.fetchedAt
    }
    func clear() {
        fingerprint = nil; models = []; fetchedAt = nil; message = nil
        UserDefaults.standard.removeObject(forKey: cacheName)
    }
    private func persist() {
        guard let fingerprint, let fetchedAt else { return }
        let cache = Cache(keyFingerprint: fingerprint, fetchedAt: fetchedAt, models: models)
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: cacheName) }
    }
    private func isCurrent(_ keyID: String) -> Bool {
        guard !Task.isCancelled, fingerprint == keyID, let key = AssistantKeychain.read() else { return false }
        return identity(key) == keyID
    }

    /// Explicit connection/refresh action. Small probes contain no habit or voice data.
    func discover(refresh: Bool) async throws {
        guard !checking else { return }
        guard let key = AssistantKeychain.read() else { throw AssistantError.message("Enter and save your NVIDIA key first.") }
        let keyID = identity(key)
        if fingerprint != keyID { clear(); fingerprint = keyID }
        checking = true; message = nil
        defer { checking = false; progress = "" }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        if refresh || models.isEmpty {
            progress = "Getting NVIDIA's model list…"
            var request = URLRequest(url: URL(string: "https://integrate.api.nvidia.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard isCurrent(keyID) else { throw CancellationError() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else {
                throw AssistantError.message("Couldn't load NVIDIA's model list. Check your key and connection.")
            }
            struct Catalog: Decodable { struct Entry: Decodable { let id: String }; let data: [Entry] }
            let ids = Set(try JSONDecoder().decode(Catalog.self, from: data).data.map(\.id))
                .filter { !$0.isEmpty && $0.count < 300 }.sorted()
            guard !ids.isEmpty, ids.count <= 1000 else { throw AssistantError.message("NVIDIA returned an unexpected model list.") }
            // An explicit refresh invalidates earlier checks. A cancelled scan can be resumed.
            models = ids.map { NVIDIAAvailableModel(id: $0) }
            fetchedAt = .now
            persist()
        }
        let todo = models.indices.filter { [.listed, .retry].contains(models[$0].status) }
        for (offset, index) in todo.enumerated() {
            guard isCurrent(keyID) else { throw CancellationError() }
            progress = "Checking \(offset + 1) of \(todo.count) · \(models[index].id)"
            var request = URLRequest(url: URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": models[index].id, "stream": false, "max_tokens": 16,
                "messages": [["role": "user", "content": "Reply with OK."]]
            ])
            do {
                let (data, response) = try await session.data(for: request)
                guard isCurrent(keyID) else { throw CancellationError() }
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 401 {
                    message = "NVIDIA rejected this key. Replace it and reconnect."
                    throw AssistantError.message(message!)
                }
                if http.statusCode == 429 {
                    models[index].status = .retry
                    models[index].detail = "Rate limited; try again later"
                    persist()
                    message = "NVIDIA asked us to slow down. Saved the results so far; resume later."
                    return
                }
                let root = data.count < 1_000_000 ? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] : nil
                let choices = root?["choices"] as? [[String: Any]]
                if (200..<300).contains(http.statusCode), let first = choices?.first,
                   first["message"] as? [String: Any] != nil {
                    models[index].status = .available
                    models[index].detail = "Responded to a chat request"
                } else if http.statusCode == 403 {
                    models[index].status = .denied
                    models[index].detail = "Access denied for this key"
                } else if [400, 404, 405, 422].contains(http.statusCode) {
                    models[index].status = .unsupported
                    models[index].detail = "Did not accept a basic chat request (\(http.statusCode))"
                } else {
                    models[index].status = .retry
                    models[index].detail = "No usable chat response (\(http.statusCode)); retry later"
                }
                models[index].checkedAt = .now
                persist()
            } catch is CancellationError { throw CancellationError() }
            catch let error as AssistantError { throw error }
            catch {
                guard isCurrent(keyID) else { throw CancellationError() }
                models[index].status = .retry
                models[index].detail = "Timed out or couldn't connect; retry later"
                models[index].checkedAt = .now
                persist()
            }
            // Sequential requests with a gap avoid flooding the account.
            try await Task.sleep(for: .milliseconds(350))
        }
        message = usable.isEmpty ? "No model responded to the chat check. Check your key access or retry later." : "Saved \(usable.count) responding chat models for this key."
    }
}
