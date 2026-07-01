import Combine
import CryptoKit
import Foundation
import Security

enum LicenseState: Equatable {
    case freeMode
    case licensed(LicensePayload)
    case missing
    case invalid(String)
    case validating
}

struct LicensePayload: Codable, Equatable {
    let codeID: String
    let issuedAt: Date
    let expiresAt: Date?
    let plan: String?
}

struct LicenseRedeemResponse: Codable {
    let token: String
}

enum LicenseError: LocalizedError {
    case notConfigured
    case emptyCode
    case invalidServerResponse
    case invalidToken
    case expired
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "License server is not configured.".loc
        case .emptyCode: return "Enter a redemption code.".loc
        case .invalidServerResponse: return "License server returned an invalid response.".loc
        case .invalidToken: return "License token is invalid.".loc
        case .expired: return "License has expired.".loc
        case .network(let message): return message
        }
    }
}

/// Future-ready license gate. It is intentionally dormant in 1.0.8 because
/// `N1KOLicenseRequired` defaults to false in Info.plist.
final class LicenseService: ObservableObject {
    static let shared = LicenseService()

    @Published private(set) var state: LicenseState = .freeMode
    @Published private(set) var lastError: String?

    private let service = "com.n1ko.state.monitor.license"
    private let account = "official-license"

    var isLicenseRequired: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "N1KOLicenseRequired") as? Bool) ?? false
    }

    var isUnlocked: Bool {
        switch state {
        case .freeMode, .licensed:
            return true
        default:
            return !isLicenseRequired
        }
    }

    func refresh() {
        guard isLicenseRequired else {
            state = .freeMode
            lastError = nil
            return
        }
        guard let token = readToken() else {
            state = .missing
            return
        }
        do {
            state = .licensed(try validate(token: token))
            lastError = nil
        } catch {
            state = .invalid(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func redeem(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await update(.invalid(LicenseError.emptyCode.localizedDescription),
                         error: LicenseError.emptyCode.localizedDescription)
            return
        }
        guard let url = redeemURL else {
            await update(.invalid(LicenseError.notConfigured.localizedDescription),
                         error: LicenseError.notConfigured.localizedDescription)
            return
        }

        await update(.validating, error: nil)
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["code": trimmed, "app": "N1KO-STATE"])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw LicenseError.network("License server rejected the code.".loc)
            }
            guard let token = try? JSONDecoder().decode(LicenseRedeemResponse.self, from: data).token else {
                throw LicenseError.invalidServerResponse
            }
            let payload = try validate(token: token)
            try save(token: token)
            await update(.licensed(payload), error: nil)
        } catch {
            await update(.invalid(error.localizedDescription), error: error.localizedDescription)
        }
    }

    func clear() {
        deleteToken()
        refresh()
    }

    private var redeemURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "N1KOLicenseRedeemURL") as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: raw)
    }

    private var publicKeyData: Data? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "N1KOLicensePublicKey") as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Data(base64Encoded: raw)
    }

    private func validate(token: String) throws -> LicensePayload {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 2,
              let payloadData = Self.base64URLDecode(parts[0]),
              let signature = Self.base64URLDecode(parts[1]) else {
            throw LicenseError.invalidToken
        }

        if let publicKeyData {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            guard publicKey.isValidSignature(signature, for: Data(parts[0].utf8)) else {
                throw LicenseError.invalidToken
            }
        } else if isLicenseRequired {
            throw LicenseError.notConfigured
        }

        let payload = try JSONDecoder.licenseDecoder.decode(LicensePayload.self, from: payloadData)
        if let expiresAt = payload.expiresAt, expiresAt < Date() {
            throw LicenseError.expired
        }
        return payload
    }

    private func readToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func save(token: String) throws {
        guard let data = token.data(using: .utf8) else { throw LicenseError.invalidToken }
        deleteToken()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw LicenseError.invalidToken }
    }

    private func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 { base64 += String(repeating: "=", count: 4 - padding) }
        return Data(base64Encoded: base64)
    }

    @MainActor
    private func update(_ state: LicenseState, error: String?) {
        self.state = state
        self.lastError = error
    }
}

private extension JSONDecoder {
    static var licenseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
