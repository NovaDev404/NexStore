//
//  SettingsView.swift
//  NexStore
//
//  Created by NovaDev404 on 24.02.2026.
//

import SwiftUI
import NimbleViews

struct MoreView: View {
	@AppStorage("NexStore.useNovaDNSDynamic") private var useNovaDNSDynamic: Bool = false
	@AppStorage(NovaCerts.autoSyncDefaultsKey) private var _autoSyncNovaCertsLocally: Bool = false
	@State private var _isSyncingNovaCerts = false

	var body: some View {
		NBList(.localized("More Settings")) {
			Section {
				HStack {
					Toggle(isOn: $useNovaDNSDynamic) {
						Text("Use NovaDNS Dynamic")
					}
					Spacer()
					Button(action: {
						guard let url = URL(string: "https://novadev.vip/resources/dns/") else { return }
						Task { @MainActor in
							await UIApplication.shared.open(url)
						}
					}) {
						Image(systemName: "questionmark.circle.fill")
							.foregroundColor(.blue)
					}
					.buttonStyle(.plain)
				}

				Toggle(.localized("Auto sync NovaCerts locally"), isOn: $_autoSyncNovaCertsLocally)

				Button {
					Task {
						await _syncNovaCertsNow()
					}
				} label: {
					HStack {
						Label(.localized("Sync NovaCerts Now"), systemImage: "arrow.triangle.2.circlepath")

						Spacer()

						if _isSyncingNovaCerts {
							ProgressView()
						}
					}
				}
				.disabled(_isSyncingNovaCerts)
			} footer: {
				Text(.localized("When enabled, NexStore checks NovaCerts whenever the app becomes active and automatically imports new official certificates that are not already stored locally."))
			}
		}
	}
}

// MARK: - Actions
extension MoreView {
	@MainActor
	private func _syncNovaCertsNow() async {
		guard !_isSyncingNovaCerts else { return }

		_isSyncingNovaCerts = true
		defer {
			_isSyncingNovaCerts = false
		}

		do {
			let importedCertificates = try await NovaCerts.syncNewCertificatesLocally()
			let message = importedCertificates.isEmpty
				? .localized("No new NovaCerts certificates were found.")
				: String(format: .localized("Imported %d new NovaCerts certificate(s)."), importedCertificates.count)

			UIAlertController.showAlertWithOk(
				title: .localized("NovaCerts Sync Complete"),
				message: message
			)
		} catch {
			UIAlertController.showAlertWithOk(
				title: .localized("NovaCerts Sync Failed"),
				message: error.localizedDescription
			)
		}
	}
}