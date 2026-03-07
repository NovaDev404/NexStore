//
//  CertificatesInfoView.swift
//  Feather
//
//  Created by samara on 20.04.2025.
//

import SwiftUI
import NimbleViews
import ZsignSwift

// MARK: - View
struct CertificatesInfoView: View {
	@Environment(\.dismiss) var dismiss
	@State var data: Certificate?
	@ObservedObject private var statusManager = CertificateStatusManager.shared
	
	var cert: CertificatePair
	
	// MARK: Body
    var body: some View {
		NBNavigationView(cert.nickname ?? "", displayMode: .inline) {
			Form {
				Section {} header: {
					Image("Cert")
						.resizable()
						.scaledToFit()
						.frame(width: 107, height: 107)
						.frame(maxWidth: .infinity, alignment: .center)
				}
				
				if let data {
					_infoSection(data: data)
					_entitlementsSection(data: data)
					_miscSection(data: data)
				}
				
				Section {
					Button(.localized("Open in Files"), systemImage: "folder") {
						UIApplication.open(Storage.shared.getUuidDirectory(for: cert)!.toSharedDocumentsURL()!)
					}
				}
			}
			.toolbar {
				NBToolbarButton(role: .close)
			}
		}
		.task(id: cert.uuid ?? cert.objectID.uriRepresentation().absoluteString) {
			data = Storage.shared.getProvisionFileDecoded(for: cert)
			statusManager.refreshStatuses(for: cert)
		}
    }
}

// MARK: - Extension: View
extension CertificatesInfoView {
	private var _deviceStatus: CertificateStatusValue {
		CertificateStatusValue.deviceStatus(for: cert)
	}

	private var _appleStatusSnapshot: CertificateAppleStatusSnapshot? {
		statusManager.appleStatus(for: cert)
	}

	private var _appleStatus: CertificateStatusValue {
		_appleStatusSnapshot?.status ?? .unknown
	}

	@ViewBuilder
	private func _infoSection(data: Certificate) -> some View {
		NBSection(.localized("Info")) {
			_info(.localized("Name"), description: data.Name)
			_info(.localized("AppID Name"), description: data.AppIDName)
			_info(.localized("Team Name"), description: data.TeamName)
		}
		
		Section {
			_info(.localized("Expires"), description: data.ExpirationDate.expirationInfo().formatted)
				.foregroundStyle(data.ExpirationDate.expirationInfo().color)

			_statusInfo(
				.localized("Device thinks this certificate is"),
				status: _deviceStatus,
				description: _deviceStatus.title,
				isRefreshing: statusManager.isRefreshingDeviceStatus(for: cert)
			)

			_statusInfo(
				.localized("Apple Status"),
				status: _appleStatus,
				description: _appleStatusSnapshot?.displayTitle ?? _appleStatus.title,
				isRefreshing: statusManager.isRefreshingAppleStatus(for: cert)
			)
			
			if let ppq = data.PPQCheck {
				_info(.localized("PPQCheck"), description: ppq ? "✓" : "✗")
			}
		}
	}
	
	@ViewBuilder
	private func _entitlementsSection(data: Certificate) -> some View {
		if let entitlements = data.Entitlements {
			Section {
				NavigationLink(.localized("View Entitlements")) {
					CertificatesInfoEntitlementView(entitlements: entitlements)
				}
			}
		}
	}
	
	@ViewBuilder
	private func _miscSection(data: Certificate) -> some View {
		NBSection(.localized("Misc")) {
			_disclosure(.localized("Platform"), keys: data.Platform)
			
			if let all = data.ProvisionsAllDevices {
				_info(.localized("Provision All Devices"), description: all.description)
			}
			
			if let devices = data.ProvisionedDevices {
				_disclosure(.localized("Provisioned Devices"), keys: devices)
			}
			
			_disclosure(.localized("Team Identifiers"), keys: data.TeamIdentifier)
			
			if let prefix = data.ApplicationIdentifierPrefix{
				_disclosure(.localized("Identifier Prefix"), keys: prefix)
			}
		}
	}
	
	@ViewBuilder
	private func _info(_ title: String, description: String) -> some View {
		LabeledContent(title) {
			Text(description)
		}
		.copyableText(description)
	}

	@ViewBuilder
	private func _statusInfo(
		_ title: String,
		status: CertificateStatusValue,
		description: String,
		isRefreshing: Bool
	) -> some View {
		let icon = isRefreshing ? "arrow.clockwise" : status.icon
		let color = isRefreshing ? Color.secondary : status.color
		let statusText = isRefreshing ? .localized("Checking") : description

		LabeledContent(title) {
			HStack(spacing: 6) {
				Image(systemName: icon)
					.foregroundStyle(color)
				Text(statusText)
					.foregroundStyle(color)
			}
		}
		.copyableText(statusText)
	}
	
	@ViewBuilder
	private func _disclosure(_ title: String, keys: [String]) -> some View {
		DisclosureGroup(title) {
			ForEach(keys, id: \.self) { key in
				Text(key)
					.foregroundStyle(.secondary)
					.copyableText(key)
			}
		}
	}
}
