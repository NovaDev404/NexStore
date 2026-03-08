import AltSign
import Foundation
import OSLog
import UIKit

@MainActor
final class AppleIDSessionManager: ObservableObject {
	struct TeamSummary: Identifiable, Codable, Equatable, Hashable, Sendable {
		let identifier: String
		let name: String
		let typeRawValue: Int16

		var id: String { identifier }
	}

	private struct AccountSnapshot: Codable {
		let appleID: String
		let displayName: String?
		let teamIdentifier: String?
		let teamName: String?
	}

	static let shared = AppleIDSessionManager()

	@Published var anisetteServerURL: String {
		didSet {
			UserDefaults.standard.set(anisetteServerURL, forKey: Self._anisetteServerURLKey)
		}
	}

	@Published var rememberCredentials: Bool {
		didSet {
			UserDefaults.standard.set(rememberCredentials, forKey: Self._rememberCredentialsKey)

			if !rememberCredentials, !savedAppleID.isEmpty {
				try? AppleIDKeychain.removeValue(for: Self._passwordAccount(for: savedAppleID))
			}
		}
	}

	@Published private(set) var savedAppleID: String
	@Published private(set) var displayName: String?
	@Published private(set) var selectedTeamIdentifier: String?
	@Published private(set) var selectedTeamName: String?
	@Published private(set) var availableTeams: [TeamSummary] = []
	@Published private(set) var hasAuthenticatedSession = false
	@Published private(set) var isBusy = false

	private var _cachedContext: AppleIDSigningContext?
	private var _teamCache: [String: ALTTeam] = [:]

	private static let _anisetteServerURLKey = "NexStore.appleID.anisetteServerURL"
	private static let _rememberCredentialsKey = "NexStore.appleID.rememberCredentials"
	private static let _accountSnapshotKey = "NexStore.appleID.snapshot"

	private init() {
		let defaults = UserDefaults.standard
		anisetteServerURL = defaults.string(forKey: Self._anisetteServerURLKey) ?? ""
		rememberCredentials = defaults.object(forKey: Self._rememberCredentialsKey) as? Bool ?? false

		if
			let data = defaults.data(forKey: Self._accountSnapshotKey),
			let snapshot = try? JSONDecoder().decode(AccountSnapshot.self, from: data)
		{
			savedAppleID = snapshot.appleID
			displayName = snapshot.displayName
			selectedTeamIdentifier = snapshot.teamIdentifier
			selectedTeamName = snapshot.teamName
		} else {
			savedAppleID = ""
			displayName = nil
			selectedTeamIdentifier = nil
			selectedTeamName = nil
		}
	}

	var hasSavedCredentials: Bool {
		guard !savedAppleID.isEmpty else {
			return false
		}

		return (try? AppleIDKeychain.string(for: Self._passwordAccount(for: savedAppleID)))?.isEmpty == false
	}

	func signIn(appleID rawAppleID: String, password rawPassword: String?) async throws {
		let appleID = rawAppleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !appleID.isEmpty else {
			throw AppleIDSessionError.missingAppleID
		}

		guard !anisetteServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw AppleIDSessionError.missingAnisetteServerURL
		}

		let password = try _resolvePassword(for: appleID, candidate: rawPassword)

		isBusy = true
		defer { isBusy = false }

		let anisetteData = try await _fetchAnisetteData()
		let authenticationResult = try await AltSignAsync.authenticate(
			appleID: appleID,
			password: password,
			anisetteData: anisetteData,
			verificationCodeProvider: Self._promptForVerificationCode
		)
		let teams = try await AltSignAsync.fetchTeams(for: authenticationResult.account, session: authenticationResult.session)

		guard !teams.isEmpty else {
			throw AppleIDSessionError.noTeams
		}

		_teamCache = Dictionary(uniqueKeysWithValues: teams.map { ($0.identifier, $0) })
		availableTeams = teams
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
			.map {
				.init(
					identifier: $0.identifier,
					name: $0.name,
					typeRawValue: $0.type.rawValue
				)
			}

		let selectedTeam = _selectedTeam(from: teams)
		_cachedContext = .init(account: authenticationResult.account, session: authenticationResult.session, team: selectedTeam)
		hasAuthenticatedSession = true

		savedAppleID = appleID
		displayName = authenticationResult.account.name
		selectedTeamIdentifier = selectedTeam.identifier
		selectedTeamName = selectedTeam.name
		_saveSnapshot()

		if rememberCredentials {
			try AppleIDKeychain.set(password, for: Self._passwordAccount(for: appleID))
		} else {
			try? AppleIDKeychain.removeValue(for: Self._passwordAccount(for: appleID))
		}

		Logger.signing.info("Authenticated Apple ID session for \(appleID, privacy: .private(mask: .hash))")
	}

	func refreshSession() async throws {
		guard !savedAppleID.isEmpty else {
			throw AppleIDSessionError.notSignedIn
		}

		try await signIn(appleID: savedAppleID, password: nil)
	}

	func requireSigningContext() async throws -> AppleIDSigningContext {
		if let _cachedContext {
			return _cachedContext
		}

		try await refreshSession()

		guard let _cachedContext else {
			throw AppleIDSessionError.notSignedIn
		}

		return _cachedContext
	}

	func selectTeam(identifier: String) {
		guard let summary = availableTeams.first(where: { $0.identifier == identifier }) else {
			return
		}

		selectedTeamIdentifier = summary.identifier
		selectedTeamName = summary.name

		if
			let context = _cachedContext,
			let team = _teamCache[summary.identifier]
		{
			_cachedContext = .init(account: context.account, session: context.session, team: team)
		}

		_saveSnapshot()
	}

	func forgetAccount() {
		if !savedAppleID.isEmpty {
			try? AppleIDKeychain.removeValue(for: Self._passwordAccount(for: savedAppleID))
		}

		_cachedContext = nil
		_teamCache = [:]
		availableTeams = []
		hasAuthenticatedSession = false
		savedAppleID = ""
		displayName = nil
		selectedTeamIdentifier = nil
		selectedTeamName = nil
		UserDefaults.standard.removeObject(forKey: Self._accountSnapshotKey)
	}

	private func _resolvePassword(for appleID: String, candidate: String?) throws -> String {
		let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if !candidate.isEmpty {
			return candidate
		}

		if let storedPassword = try AppleIDKeychain.string(for: Self._passwordAccount(for: appleID)), !storedPassword.isEmpty {
			return storedPassword
		}

		throw AppleIDSessionError.missingPassword
	}

	private func _selectedTeam(from teams: [ALTTeam]) -> ALTTeam {
		if let selectedTeamIdentifier, let selectedTeam = teams.first(where: { $0.identifier == selectedTeamIdentifier }) {
			return selectedTeam
		}

		if let freeTeam = teams.first(where: { $0.type == .free }) {
			return freeTeam
		}

		return teams[0]
	}

	private func _saveSnapshot() {
		guard !savedAppleID.isEmpty else {
			UserDefaults.standard.removeObject(forKey: Self._accountSnapshotKey)
			return
		}

		let snapshot = AccountSnapshot(
			appleID: savedAppleID,
			displayName: displayName,
			teamIdentifier: selectedTeamIdentifier,
			teamName: selectedTeamName
		)

		guard let data = try? JSONEncoder().encode(snapshot) else {
			return
		}

		UserDefaults.standard.set(data, forKey: Self._accountSnapshotKey)
	}

	private func _fetchAnisetteData() async throws -> ALTAnisetteData {
		let urlString = anisetteServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: urlString) else {
			throw AppleIDSessionError.invalidAnisetteServerURL
		}

		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 30

		let (data, response) = try await URLSession.shared.data(for: request)
		guard
			let httpResponse = response as? HTTPURLResponse,
			(200...299).contains(httpResponse.statusCode)
		else {
			throw AppleIDSessionError.invalidAnisetteResponse
		}

		guard let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw AppleIDSessionError.invalidAnisetteResponse
		}

		let json = rawJSON.reduce(into: [String: String]()) { partialResult, entry in
			switch entry.value {
			case let string as String:
				partialResult[entry.key] = string
			case let number as NSNumber:
				partialResult[entry.key] = number.stringValue
			default:
				break
			}
		}

		guard let anisetteData = ALTAnisetteData(json: json) else {
			throw AppleIDSessionError.invalidAnisetteResponse
		}

		return anisetteData
	}

	private static func _promptForVerificationCode() async -> String? {
		await withCheckedContinuation { continuation in
			guard let presenter = UIApplication.topViewController() else {
				continuation.resume(returning: nil)
				return
			}

			let alert = UIAlertController(
				title: .localized("Two-Factor Authentication"),
				message: .localized("Enter the verification code sent to your trusted device or phone number."),
				preferredStyle: .alert
			)
			alert.addTextField { textField in
				textField.placeholder = .localized("Verification Code")
				textField.keyboardType = .numberPad
				textField.textContentType = .oneTimeCode
			}
			alert.addAction(UIAlertAction(title: .localized("Cancel"), style: .cancel) { _ in
				continuation.resume(returning: nil)
			})
			alert.addAction(UIAlertAction(title: .localized("OK"), style: .default) { _ in
				let code = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
				continuation.resume(returning: code?.isEmpty == false ? code : nil)
			})

			presenter.present(alert, animated: true)
		}
	}

	private static func _passwordAccount(for appleID: String) -> String {
		"password.\(appleID.lowercased())"
	}
}

private enum AppleIDSessionError: LocalizedError {
	case missingAppleID
	case missingPassword
	case notSignedIn
	case noTeams
	case missingAnisetteServerURL
	case invalidAnisetteServerURL
	case invalidAnisetteResponse

	var errorDescription: String? {
		switch self {
		case .missingAppleID:
			String.localized("Enter your Apple ID email address.")
		case .missingPassword:
			String.localized("Enter your password or enable saved credentials.")
		case .notSignedIn:
			String.localized("Apple ID signing requires a signed-in Apple ID.")
		case .noTeams:
			String.localized("This Apple ID does not have any developer teams available.")
		case .missingAnisetteServerURL:
			String.localized("Enter your anisette server URL before signing in.")
		case .invalidAnisetteServerURL:
			String.localized("The configured anisette server URL is invalid.")
		case .invalidAnisetteResponse:
			String.localized("The anisette server did not return valid anisette data.")
		}
	}
}