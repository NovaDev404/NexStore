import AltSign
import Foundation
import UIKit

enum AppleIDSigningCoordinator {
	static func sign(appAt appURL: URL, context: AppleIDSigningContext) async throws {
		let device = try _deviceInfo()
		try await _ensureDeviceIsRegistered(device, context: context)
		let certificate = try await _signingCertificate(for: context)
		let profiles = try await _provisioningProfiles(for: appURL, context: context, deviceType: device.type)
		try await AltSignAsync.signApp(
			at: appURL,
			team: context.team,
			certificate: certificate,
			provisioningProfiles: profiles
		)
	}
}

private extension AppleIDSigningCoordinator {
	struct DeviceInfo {
		let name: String
		let identifier: String
		let type: ALTDeviceType
	}

	static func _deviceInfo() throws -> DeviceInfo {
		let mobileGestalt = MobileGestalt()
		let identifier = ["UniqueDeviceID", "UniqueChipID"]
			.compactMap { mobileGestalt.getStringForName($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.first(where: { !$0.isEmpty })

		guard let identifier else {
			throw AppleIDSigningError.missingDeviceIdentifier
		}

		let type: ALTDeviceType = UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
		return .init(name: UIDevice.current.name, identifier: identifier, type: type)
	}

	static func _ensureDeviceIsRegistered(_ device: DeviceInfo, context: AppleIDSigningContext) async throws {
		let devices = try await AltSignAsync.fetchDevices(for: context.team, types: device.type, session: context.session)
		if devices.contains(where: { $0.identifier.caseInsensitiveCompare(device.identifier) == .orderedSame }) {
			return
		}

		do {
			_ = try await AltSignAsync.registerDevice(
				name: device.name,
				identifier: device.identifier,
				type: device.type,
				team: context.team,
				session: context.session
			)
		} catch {
			let refreshedDevices = try await AltSignAsync.fetchDevices(for: context.team, types: device.type, session: context.session)
			guard refreshedDevices.contains(where: { $0.identifier.caseInsensitiveCompare(device.identifier) == .orderedSame }) else {
				throw error
			}
		}
	}

	static func _signingCertificate(for context: AppleIDSigningContext) async throws -> ALTCertificate {
		let portalCertificates = try await AltSignAsync.fetchCertificates(for: context.team, session: context.session)

		if let storedCertificate = _loadStoredCertificate(teamIdentifier: context.team.identifier) {
			if portalCertificates.contains(where: { $0.serialNumber.caseInsensitiveCompare(storedCertificate.serialNumber) == .orderedSame }) {
				return storedCertificate
			}
		}

		do {
			let certificate = try await AltSignAsync.addCertificate(
				machineName: UIDevice.current.name,
				to: context.team,
				session: context.session
			)
			try _storeCertificate(certificate, teamIdentifier: context.team.identifier)
			return certificate
		} catch {
			for portalCertificate in portalCertificates {
				do {
					try await AltSignAsync.revoke(portalCertificate, for: context.team, session: context.session)
					let replacementCertificate = try await AltSignAsync.addCertificate(
						machineName: UIDevice.current.name,
						to: context.team,
						session: context.session
					)
					try _storeCertificate(replacementCertificate, teamIdentifier: context.team.identifier)
					return replacementCertificate
				} catch {
					continue
				}
			}

			throw error
		}
	}

	static func _loadStoredCertificate(teamIdentifier: String) -> ALTCertificate? {
		guard
			let data = try? AppleIDKeychain.data(for: _certificateAccount(for: teamIdentifier)),
			let data,
			let certificate = ALTCertificate(p12Data: data, password: "")
		else {
			return nil
		}

		return certificate
	}

	static func _storeCertificate(_ certificate: ALTCertificate, teamIdentifier: String) throws {
		guard let p12Data = certificate.p12Data() else {
			throw AppleIDSigningError.invalidCertificateData
		}

		try AppleIDKeychain.set(p12Data, for: _certificateAccount(for: teamIdentifier))
	}

	static func _provisioningProfiles(
		for appURL: URL,
		context: AppleIDSigningContext,
		deviceType: ALTDeviceType
	) async throws -> [ALTProvisioningProfile] {
		guard let application = ALTApplication(fileURL: appURL) else {
			throw AppleIDSigningError.invalidApplication
		}

		var allApplications = [application]
		allApplications.append(contentsOf: Array(application.appExtensions))

		var appIDsByBundleIdentifier = Dictionary(
			uniqueKeysWithValues: try await AltSignAsync.fetchAppIDs(for: context.team, session: context.session)
				.map { ($0.bundleIdentifier, $0) }
		)
		var appGroupsByIdentifier = Dictionary(
			uniqueKeysWithValues: try await AltSignAsync.fetchAppGroups(for: context.team, session: context.session)
				.map { ($0.identifier, $0) }
		)

		var provisioningProfiles: [ALTProvisioningProfile] = []
		for application in allApplications {
			let appID = try await _appID(
				for: application,
				context: context,
				appIDsByBundleIdentifier: &appIDsByBundleIdentifier,
				appGroupsByIdentifier: &appGroupsByIdentifier
			)

			let profile = try await AltSignAsync.fetchProvisioningProfile(
				for: appID,
				deviceType: deviceType,
				team: context.team,
				session: context.session
			)
			provisioningProfiles.append(profile)
		}

		return provisioningProfiles
	}

	static func _appID(
		for application: ALTApplication,
		context: AppleIDSigningContext,
		appIDsByBundleIdentifier: inout [String: ALTAppID],
		appGroupsByIdentifier: inout [String: ALTAppGroup]
	) async throws -> ALTAppID {
		let bundleIdentifier = application.bundleIdentifier
		var appID = appIDsByBundleIdentifier[bundleIdentifier]

		if appID == nil {
			appID = try await AltSignAsync.addAppID(
				name: application.name,
				bundleIdentifier: bundleIdentifier,
				team: context.team,
				session: context.session
			)
		}

		guard var appID else {
			throw AppleIDSigningError.invalidApplication
		}

		let entitlements = _sanitizedEntitlements(from: application)
		let appGroups = (entitlements["com.apple.security.application-groups"] as? [String]) ?? []

		appID.entitlements = entitlements
		appID.features = _features(from: entitlements)
		appID = try await AltSignAsync.update(appID, team: context.team, session: context.session)

		if !appGroups.isEmpty {
			let groups = try await _appGroups(
				matching: appGroups,
				context: context,
				appGroupsByIdentifier: &appGroupsByIdentifier
			)
			try await AltSignAsync.assign(appID: appID, toGroups: groups, team: context.team, session: context.session)
		}

		appIDsByBundleIdentifier[bundleIdentifier] = appID
		return appID
	}

	static func _appGroups(
		matching identifiers: [String],
		context: AppleIDSigningContext,
		appGroupsByIdentifier: inout [String: ALTAppGroup]
	) async throws -> [ALTAppGroup] {
		var groups: [ALTAppGroup] = []

		for identifier in identifiers {
			if let group = appGroupsByIdentifier[identifier] {
				groups.append(group)
				continue
			}

			let group = try await AltSignAsync.addAppGroup(
				name: identifier.components(separatedBy: ".").last ?? identifier,
				groupIdentifier: identifier,
				team: context.team,
				session: context.session
			)
			appGroupsByIdentifier[identifier] = group
			groups.append(group)
		}

		return groups
	}

	static func _sanitizedEntitlements(from application: ALTApplication) -> [String: Any] {
		let ignoredEntitlements: Set<String> = [
			"application-identifier",
			"com.apple.developer.team-identifier",
			"get-task-allow",
			"keychain-access-groups",
		]

		var entitlements: [String: Any] = [:]
		for (key, value) in application.entitlements {
			let entitlement = key as String
			guard !ignoredEntitlements.contains(entitlement) else {
				continue
			}

			entitlements[entitlement] = value
		}

		return entitlements
	}

	static func _features(from entitlements: [String: Any]) -> [String: Any] {
		var features: [String: Any] = [:]

		for (entitlement, value) in entitlements {
			if let feature = ALTFeature(entitlement: entitlement) {
				features[feature] = value
			}
		}

		return features
	}

	static func _certificateAccount(for teamIdentifier: String) -> String {
		"certificate.\(teamIdentifier)"
	}
}

private enum AppleIDSigningError: LocalizedError {
	case missingDeviceIdentifier
	case invalidCertificateData
	case invalidApplication

	var errorDescription: String? {
		switch self {
		case .missingDeviceIdentifier:
			String.localized("The current device UDID could not be determined.")
		case .invalidCertificateData:
			String.localized("The Apple ID signing certificate could not be stored.")
		case .invalidApplication:
			String.localized("The selected app could not be prepared for Apple ID signing.")
		}
	}
}