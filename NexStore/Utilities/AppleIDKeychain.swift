import Foundation
import Security

enum AppleIDKeychainError: LocalizedError {
	case unhandledStatus(OSStatus)

	var errorDescription: String? {
		switch self {
		case .unhandledStatus(let status):
			"Keychain error (\(status))."
		}
	}
}

enum AppleIDKeychain {
	private static let _service = (Bundle.main.bundleIdentifier ?? "com.novadev.nexstore") + ".apple-id"

	static func data(for account: String) throws -> Data? {
		var query = _query(for: account)
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		switch status {
		case errSecSuccess:
			return item as? Data
		case errSecItemNotFound:
			return nil
		default:
			throw AppleIDKeychainError.unhandledStatus(status)
		}
	}

	static func string(for account: String) throws -> String? {
		guard let data = try data(for: account) else {
			return nil
		}

		return String(data: data, encoding: .utf8)
	}

	static func set(_ value: String, for account: String) throws {
		guard let data = value.data(using: .utf8) else {
			throw AppleIDKeychainError.unhandledStatus(errSecParam)
		}

		try set(data, for: account)
	}

	static func set(_ value: Data, for account: String) throws {
		let query = _query(for: account)
		let attributes = [kSecValueData as String: value]

		let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
		switch updateStatus {
		case errSecSuccess:
			return
		case errSecItemNotFound:
			var addQuery = query
			addQuery[kSecValueData as String] = value

			let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
			guard addStatus == errSecSuccess else {
				throw AppleIDKeychainError.unhandledStatus(addStatus)
			}
		default:
			throw AppleIDKeychainError.unhandledStatus(updateStatus)
		}
	}

	static func removeValue(for account: String) throws {
		let status = SecItemDelete(_query(for: account) as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw AppleIDKeychainError.unhandledStatus(status)
		}
	}

	private static func _query(for account: String) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: _service,
			kSecAttrAccount as String: account,
		]
	}
}