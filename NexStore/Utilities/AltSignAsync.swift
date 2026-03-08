import AltSign
import Foundation

typealias AppleIDVerificationCodeProvider = @MainActor () async -> String?

struct AltSignAuthenticationResult: @unchecked Sendable {
	let account: ALTAccount
	let session: ALTAppleAPISession
}

struct AppleIDSigningContext: @unchecked Sendable {
	let account: ALTAccount
	let session: ALTAppleAPISession
	let team: ALTTeam
}

enum AltSignAsync {
	static func authenticate(
		appleID: String,
		password: String,
		anisetteData: ALTAnisetteData,
		verificationCodeProvider: @escaping AppleIDVerificationCodeProvider
	) async throws -> AltSignAuthenticationResult {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.authenticate(
				appleID: appleID,
				password: password,
				anisetteData: anisetteData,
				verificationHandler: { completionHandler in
					Task { @MainActor in
						completionHandler(await verificationCodeProvider())
					}
				},
				completionHandler: { account, session, error in
					if let error {
						continuation.resume(throwing: error)
						return
					}

					guard let account, let session else {
						continuation.resume(throwing: URLError(.userAuthenticationRequired))
						return
					}

					continuation.resume(returning: .init(account: account, session: session))
				}
			)
		}
	}

	static func fetchTeams(for account: ALTAccount, session: ALTAppleAPISession) async throws -> [ALTTeam] {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.fetchTeams(for: account, session: session) { teams, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				continuation.resume(returning: teams ?? [])
			}
		}
	}

	static func fetchDevices(for team: ALTTeam, types: ALTDeviceType, session: ALTAppleAPISession) async throws -> [ALTDevice] {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.fetchDevices(for: team, types: types, session: session) { devices, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				continuation.resume(returning: devices ?? [])
			}
		}
	}

	static func registerDevice(
		name: String,
		identifier: String,
		type: ALTDeviceType,
		team: ALTTeam,
		session: ALTAppleAPISession
	) async throws -> ALTDevice {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.registerDevice(
				name: name,
				identifier: identifier,
				type: type,
				team: team,
				session: session
			) { device, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let device else {
					continuation.resume(throwing: URLError(.badServerResponse))
					return
				}

				continuation.resume(returning: device)
			}
		}
	}

	static func fetchCertificates(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTCertificate] {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.fetchCertificates(for: team, session: session) { certificates, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				continuation.resume(returning: certificates ?? [])
			}
		}
	}

	static func addCertificate(machineName: String, to team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.addCertificate(machineName: machineName, to: team, session: session) { certificate, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let certificate else {
					continuation.resume(throwing: URLError(.badServerResponse))
					return
				}

				continuation.resume(returning: certificate)
			}
		}
	}

	static func revoke(_ certificate: ALTCertificate, for team: ALTTeam, session: ALTAppleAPISession) async throws {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.revoke(certificate, for: team, session: session) { success, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard success else {
					continuation.resume(throwing: URLError(.cannotWriteToFile))
					return
				}

				continuation.resume()
			}
		}
	}

	static func fetchAppIDs(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppID] {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.fetchAppIDs(for: team, session: session) { appIDs, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				continuation.resume(returning: appIDs ?? [])
			}
		}
	}

	static func addAppID(
		name: String,
		bundleIdentifier: String,
		team: ALTTeam,
		session: ALTAppleAPISession
	) async throws -> ALTAppID {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.addAppID(
				name: name,
				bundleIdentifier: bundleIdentifier,
				team: team,
				session: session
			) { appID, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let appID else {
					continuation.resume(throwing: URLError(.badServerResponse))
					return
				}

				continuation.resume(returning: appID)
			}
		}
	}

	static func update(_ appID: ALTAppID, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.update(appID, team: team, session: session) { updatedAppID, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let updatedAppID else {
					continuation.resume(throwing: URLError(.badServerResponse))
					return
				}

				continuation.resume(returning: updatedAppID)
			}
		}
	}

	static func fetchAppGroups(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppGroup] {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.fetchAppGroups(for: team, session: session) { groups, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				continuation.resume(returning: groups ?? [])
			}
		}
	}

	static func addAppGroup(
		name: String,
		groupIdentifier: String,
		team: ALTTeam,
		session: ALTAppleAPISession
	) async throws -> ALTAppGroup {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.addAppGroup(
				name: name,
				groupIdentifier: groupIdentifier,
				team: team,
				session: session
			) { group, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let group else {
					continuation.resume(throwing: URLError(.badServerResponse))
					return
				}

				continuation.resume(returning: group)
			}
		}
	}

	static func assign(appID: ALTAppID, toGroups groups: [ALTAppGroup], team: ALTTeam, session: ALTAppleAPISession) async throws {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.assign(appID, toGroups: groups, team: team, session: session) { success, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard success else {
					continuation.resume(throwing: URLError(.cannotWriteToFile))
					return
				}

				continuation.resume()
			}
		}
	}

	static func fetchProvisioningProfile(
		for appID: ALTAppID,
		deviceType: ALTDeviceType,
		team: ALTTeam,
		session: ALTAppleAPISession
	) async throws -> ALTProvisioningProfile {
		try await withCheckedThrowingContinuation { continuation in
			ALTAppleAPI.sharedAPI.fetchProvisioningProfile(
				for: appID,
				deviceType: deviceType,
				team: team,
				session: session
			) { profile, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let profile else {
					continuation.resume(throwing: URLError(.badServerResponse))
					return
				}

				continuation.resume(returning: profile)
			}
		}
	}

	static func signApp(
		at appURL: URL,
		team: ALTTeam,
		certificate: ALTCertificate,
		provisioningProfiles: [ALTProvisioningProfile]
	) async throws {
		let signer = ALTSigner(team: team, certificate: certificate)

		try await withCheckedThrowingContinuation { continuation in
			_ = signer.signApp(at: appURL, provisioningProfiles: provisioningProfiles) { success, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard success else {
					continuation.resume(throwing: URLError(.cannotWriteToFile))
					return
				}

				continuation.resume()
			}
		}
	}
}