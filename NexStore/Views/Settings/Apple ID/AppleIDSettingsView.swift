import SwiftUI
import NimbleViews

struct AppleIDSettingsView: View {
	@StateObject private var _manager = AppleIDSessionManager.shared
	@State private var _appleID: String
	@State private var _password: String = ""

	init() {
		_appleID = State(initialValue: AppleIDSessionManager.shared.savedAppleID)
	}

	var body: some View {
		NBList(.localized("Apple ID")) {
			NBSection(.localized("Account")) {
				TextField(.localized("Apple ID"), text: $_appleID)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()

				SecureField(.localized("Password"), text: $_password)

				Toggle(.localized("Save Credentials"), isOn: $_manager.rememberCredentials)

				Button(_manager.isBusy ? .localized("Signing In…") : .localized("Sign In"), systemImage: "person.crop.circle.badge.checkmark") {
					_signIn()
				}
				.disabled(_manager.isBusy)

				if _manager.hasSavedCredentials {
					Button(.localized("Refresh Session"), systemImage: "arrow.clockwise") {
						_refreshSession()
					}
					.disabled(_manager.isBusy)
				}

				if !_manager.savedAppleID.isEmpty {
					Button(.localized("Forget Apple ID"), systemImage: "trash", role: .destructive) {
						_manager.forgetAccount()
						_appleID = ""
						_password = ""
					}
					.disabled(_manager.isBusy)
				}
			} footer: {
				Text(.localized("Sign in with your Apple ID to enable Apple ID signing. Two-factor authentication is supported during sign in."))
			}

			NBSection(.localized("Status")) {
				if _manager.savedAppleID.isEmpty {
					Text(.localized("No Apple ID Configured"))
						.font(.footnote)
						.foregroundColor(.disabled())
				} else {
					LabeledContent(.localized("Account")) {
						Text(_manager.savedAppleID)
					}

					if let displayName = _manager.displayName, !displayName.isEmpty {
						LabeledContent(.localized("Name")) {
							Text(displayName)
						}
					}

					if let teamName = _manager.selectedTeamName {
						LabeledContent(.localized("Team")) {
							Text(teamName)
						}
					}

					LabeledContent(.localized("Session")) {
						if _manager.hasAuthenticatedSession {
							Text(.localized("Authenticated"))
						} else if _manager.hasSavedCredentials {
							Text(.localized("Saved Credentials"))
						} else {
							Text(.localized("Needs Sign In"))
						}
					}

					if !_manager.availableTeams.isEmpty {
						Picker(.localized("Team"), selection: Binding(
							get: { _manager.selectedTeamIdentifier ?? _manager.availableTeams.first?.identifier ?? "" },
							set: { _manager.selectTeam(identifier: $0) }
						)) {
							ForEach(_manager.availableTeams) { team in
								Text(team.name).tag(team.identifier)
							}
						}
					}
				}
			}

			NBSection(.localized("Anisette")) {
				TextField(.localized("Anisette Server URL"), text: $_manager.anisetteServerURL)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.URL)
			} footer: {
				Text(.localized("Enter the full anisette endpoint URL used to generate Apple authentication headers."))
			}
		}
		.onAppear {
			_appleID = _manager.savedAppleID
		}
	}
}

private extension AppleIDSettingsView {
	func _signIn() {
		Task {
			do {
				try await _manager.signIn(appleID: _appleID, password: _password)
				_appleID = _manager.savedAppleID
				_password = ""
			} catch {
				UIAlertController.showAlertWithOk(title: .localized("Apple ID"), message: error.localizedDescription)
			}
		}
	}

	func _refreshSession() {
		Task {
			do {
				try await _manager.refreshSession()
			} catch {
				UIAlertController.showAlertWithOk(title: .localized("Apple ID"), message: error.localizedDescription)
			}
		}
	}
}