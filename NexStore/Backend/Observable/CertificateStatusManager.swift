//
//  CertificateStatusManager.swift
//  NexStore
//
//  Created by NovaDev404 on 08.03.2026.
//

import Foundation
import SwiftUI

enum CertificateStatusValue: String, Codable {
	case signed
	case revoked
	case unknown

	init(apiStatus: String) {
		let normalizedStatus = apiStatus.lowercased()

		if normalizedStatus.contains("signed") {
			self = .signed
		} else if normalizedStatus.contains("revoked") {
			self = .revoked
		} else {
			self = .unknown
		}
	}

	static func deviceStatus(for cert: CertificatePair) -> CertificateStatusValue {
		cert.revoked == true ? .revoked : .signed
	}

	var title: String {
		switch self {
		case .signed:
			NSLocalizedString("Signed", comment: "")
		case .revoked:
			NSLocalizedString("Revoked", comment: "")
		case .unknown:
			NSLocalizedString("Unknown", comment: "")
		}
	}

	var icon: String {
		switch self {
		case .signed:
			"checkmark.seal"
		case .revoked:
			"xmark.octagon"
		case .unknown:
			"questionmark.circle"
		}
	}

	var color: Color {
		switch self {
		case .signed:
			.green
		case .revoked:
			.red
		case .unknown:
			.secondary
		}
	}
}

struct CertificateAppleStatusSnapshot: Codable, Equatable {
	let status: CertificateStatusValue
	let rawValue: String
	let checkedAt: Date

	var displayTitle: String {
		let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmedValue.isEmpty ? status.title : trimmedValue
	}
}

@MainActor
final class CertificateStatusManager: ObservableObject {
	static let shared = CertificateStatusManager()

	@Published private(set) var appleStatusSnapshots: [String: CertificateAppleStatusSnapshot]
	@Published private(set) var refreshingAppleStatusIDs: Set<String> = []
	@Published private(set) var refreshingDeviceStatusIDs: Set<String> = []

	private let _checkerURL = URL(string: "https://certchecker.novadev.vip/checkCert")!
	private let _storageKey = "NexStore.certificate.appleStatusSnapshots"
	private let _statusMaxAge: TimeInterval = 30 * 60

	private init() {
		if
			let data = UserDefaults.standard.data(forKey: _storageKey),
			let snapshots = try? JSONDecoder().decode([String: CertificateAppleStatusSnapshot].self, from: data)
		{
			self.appleStatusSnapshots = snapshots
		} else {
			self.appleStatusSnapshots = [:]
		}
	}

	func appleStatus(for cert: CertificatePair) -> CertificateAppleStatusSnapshot? {
		guard let uuid = cert.uuid else {
			return nil
		}

		return appleStatusSnapshots[uuid]
	}

	func effectiveStatus(for cert: CertificatePair) -> CertificateStatusValue {
		guard let snapshot = appleStatus(for: cert), snapshot.status != .unknown else {
			return CertificateStatusValue.deviceStatus(for: cert)
		}

		return snapshot.status
	}

	func effectiveStatusTitle(for cert: CertificatePair) -> String {
		guard let snapshot = appleStatus(for: cert), snapshot.status != .unknown else {
			return CertificateStatusValue.deviceStatus(for: cert).title
		}

		return snapshot.displayTitle
	}

	func hasFreshAppleStatus(for cert: CertificatePair) -> Bool {
		guard let uuid = cert.uuid else {
			return false
		}

		return !_shouldRefreshAppleStatus(for: uuid)
	}

	func isRefreshingAppleStatus(for cert: CertificatePair) -> Bool {
		guard let uuid = cert.uuid else {
			return false
		}

		return refreshingAppleStatusIDs.contains(uuid)
	}

	func isRefreshingDeviceStatus(for cert: CertificatePair) -> Bool {
		guard let uuid = cert.uuid else {
			return false
		}

		return refreshingDeviceStatusIDs.contains(uuid)
	}

	func refreshAppleStatusIfNeeded(for cert: CertificatePair) {
		guard let uuid = cert.uuid else {
			return
		}

		guard _shouldRefreshAppleStatus(for: uuid) else {
			return
		}

		refreshAppleStatus(for: cert, force: false)
	}

	func refreshStatusIfNeeded(for cert: CertificatePair) {
		refreshAppleStatusIfNeeded(for: cert)
	}

	func refreshAppleStatus(for cert: CertificatePair, force: Bool = true) {
		guard
			let uuid = cert.uuid,
			let p12URL = Storage.shared.getFile(.certificate, from: cert)
		else {
			return
		}

		if refreshingAppleStatusIDs.contains(uuid) {
			return
		}

		guard force || _shouldRefreshAppleStatus(for: uuid) else {
			return
		}

		refreshingAppleStatusIDs.insert(uuid)

		let password = cert.password ?? ""

		Task { [checkerURL = _checkerURL] in
			defer {
				refreshingAppleStatusIDs.remove(uuid)
			}

			do {
				let snapshot = try await Self._fetchAppleStatus(
					from: checkerURL,
					p12URL: p12URL,
					password: password
				)

				appleStatusSnapshots[uuid] = snapshot
				_persistAppleStatuses()
			} catch {
				return
			}
		}
	}

	func refreshStatus(for cert: CertificatePair, forceRemote: Bool = true) {
		guard let uuid = cert.uuid else {
			return
		}

		if !refreshingDeviceStatusIDs.contains(uuid) {
			refreshingDeviceStatusIDs.insert(uuid)

			Storage.shared.revokagedCertificate(for: cert) { _ in
				Task { @MainActor in
					self.refreshingDeviceStatusIDs.remove(uuid)
				}
			}
		}

		refreshAppleStatus(for: cert, force: forceRemote)
	}

	func removeAppleStatus(for cert: CertificatePair) {
		guard let uuid = cert.uuid else {
			return
		}

		appleStatusSnapshots.removeValue(forKey: uuid)
		refreshingAppleStatusIDs.remove(uuid)
		refreshingDeviceStatusIDs.remove(uuid)
		_persistAppleStatuses()
	}

	private func _shouldRefreshAppleStatus(for uuid: String) -> Bool {
		guard let snapshot = appleStatusSnapshots[uuid] else {
			return true
		}

		return abs(snapshot.checkedAt.timeIntervalSinceNow) > _statusMaxAge
	}

	private func _persistAppleStatuses() {
		guard let data = try? JSONEncoder().encode(appleStatusSnapshots) else {
			return
		}

		UserDefaults.standard.set(data, forKey: _storageKey)
	}

	private static func _fetchAppleStatus(
		from url: URL,
		p12URL: URL,
		password: String
	) async throws -> CertificateAppleStatusSnapshot {
		let p12Data = try await Task.detached(priority: .userInitiated) {
			try Data(contentsOf: p12URL)
		}.value

		let boundary = "Boundary-\(UUID().uuidString)"
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.timeoutInterval = 30
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("NexStore/1.0", forHTTPHeaderField: "User-Agent")
		request.httpBody = _multipartBody(boundary: boundary, p12Data: p12Data, password: password)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
			throw CertificateStatusError.invalidResponse
		}

		let payload = try JSONDecoder().decode(CertCheckerResponse.self, from: data)
		let rawStatus = payload.p12.status.trimmingCharacters(in: .whitespacesAndNewlines)

		return CertificateAppleStatusSnapshot(
			status: CertificateStatusValue(apiStatus: rawStatus),
			rawValue: rawStatus,
			checkedAt: Date()
		)
	}

	private static func _multipartBody(boundary: String, p12Data: Data, password: String) -> Data {
		var body = Data()

		_append("--\(boundary)\r\n", to: &body)
		_append("Content-Disposition: form-data; name=\"p12\"; filename=\"cert.p12\"\r\n", to: &body)
		_append("Content-Type: application/x-pkcs12\r\n\r\n", to: &body)
		body.append(p12Data)
		_append("\r\n", to: &body)

		_append("--\(boundary)\r\n", to: &body)
		_append("Content-Disposition: form-data; name=\"password\"\r\n\r\n", to: &body)
		_append(password, to: &body)
		_append("\r\n", to: &body)

		_append("--\(boundary)--\r\n", to: &body)
		return body
	}

	private static func _append(_ string: String, to data: inout Data) {
		data.append(Data(string.utf8))
	}
}

private enum CertificateStatusError: LocalizedError {
	case invalidResponse

	var errorDescription: String? {
		switch self {
		case .invalidResponse:
			String.localized("The Apple certificate status check failed.")
		}
	}
}

private struct CertCheckerResponse: Decodable {
	let p12: P12Response

	struct P12Response: Decodable {
		let status: String

		enum CodingKeys: String, CodingKey {
			case status = "Status"
		}
	}
}