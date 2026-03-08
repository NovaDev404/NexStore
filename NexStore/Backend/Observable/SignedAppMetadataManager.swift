import Foundation

struct SignedAppMetadata: Codable, Equatable, Sendable {
	let signingMethod: Options.SigningMethod
	let requiresIdeviceInstall: Bool
}

enum SignedAppMetadataManager {
	private static let _storageKey = "NexStore.signedAppMetadata"

	static func metadata(for uuid: String?) -> SignedAppMetadata? {
		guard
			let uuid,
			let entry = _entries()[uuid]
		else {
			return nil
		}

		return entry
	}

	static func requiresIdeviceInstall(for app: AppInfoPresentable) -> Bool {
		metadata(for: app.uuid)?.requiresIdeviceInstall == true
	}

	static func setMetadata(_ metadata: SignedAppMetadata?, for uuid: String) {
		var entries = _entries()

		if let metadata {
			entries[uuid] = metadata
		} else {
			entries.removeValue(forKey: uuid)
		}

		_save(entries)
	}

	static func removeMetadata(for uuid: String?) {
		guard let uuid else {
			return
		}

		setMetadata(nil, for: uuid)
	}

	private static func _entries() -> [String: SignedAppMetadata] {
		guard
			let data = UserDefaults.standard.data(forKey: _storageKey),
			let entries = try? JSONDecoder().decode([String: SignedAppMetadata].self, from: data)
		else {
			return [:]
		}

		return entries
	}

	private static func _save(_ entries: [String: SignedAppMetadata]) {
		guard let data = try? JSONEncoder().encode(entries) else {
			return
		}

		UserDefaults.standard.set(data, forKey: _storageKey)
	}
}