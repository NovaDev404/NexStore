//
//  CertificateCellView.swift
//  Feather
//
//  Created by samara on 16.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct CertificatesCellView: View {
	@State var data: Certificate?
	
	@ObservedObject var cert: CertificatePair
	@ObservedObject private var statusManager = CertificateStatusManager.shared
	
	// MARK: Body
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			let title = {
				var title = cert.nickname ?? data?.Name ?? .localized("Unknown")
				
				if let getTaskAllow = data?.Entitlements?["get-task-allow"]?.value as? Bool, getTaskAllow == true {
					title = "🐞 \(title)"
				}
				
				return title
			}()
			
			NBTitleWithSubtitleView(
				title: title,
				subtitle: data?.AppIDName ?? .localized("Unknown")
			)
			
			_certInfoPill(data: cert)
		}
		.frame(minHeight: 104)
		.contentTransition(.opacity)
		.frame(maxWidth: .infinity, alignment: .leading)
		.onAppear {
			withAnimation {
				data = Storage.shared.getProvisionFileDecoded(for: cert)
			}
		}
		.task(id: cert.uuid ?? cert.objectID.uriRepresentation().absoluteString) {
			statusManager.refreshAppleStatusIfNeeded(for: cert)
		}
	}
}

// MARK: - Extension: View
extension CertificatesCellView {
	@ViewBuilder
	private func _certInfoPill(data: CertificatePair) -> some View {
		let statusPills = _buildStatusPills(from: data)
		let metadataPills = _buildMetadataPills(from: data)

		VStack(spacing: 6) {
			_pillRow(statusPills)

			if !metadataPills.isEmpty {
				_pillRow(metadataPills)
			}
		}
	}
	
	@ViewBuilder
	private func _pillRow(_ pillItems: [NBPillItem]) -> some View {
		HStack(spacing: 6) {
			ForEach(pillItems.indices, id: \.hashValue) { index in
				let pill = pillItems[index]
				NBPillView(
					title: pill.title,
					icon: pill.icon,
					color: pill.color,
					index: index,
					count: pillItems.count
				)
			}
		}
	}

	private func _buildStatusPills(from cert: CertificatePair) -> [NBPillItem] {
		let deviceStatus = CertificateStatusValue.deviceStatus(for: cert)
		let appleStatus = statusManager.appleStatus(for: cert)?.status ?? .unknown
		let isRefreshingDeviceStatus = statusManager.isRefreshingDeviceStatus(for: cert)
		let isRefreshingAppleStatus = statusManager.isRefreshingAppleStatus(for: cert)

		return [
			_statusPill(
				title: String.localized(
					"Device %@",
					arguments: isRefreshingDeviceStatus ? String.localized("Checking") : deviceStatus.title
				),
				status: deviceStatus,
				isRefreshing: isRefreshingDeviceStatus
			),
			_statusPill(
				title: String.localized(
					"Apple %@",
					arguments: isRefreshingAppleStatus ? String.localized("Checking") : appleStatus.title
				),
				status: appleStatus,
				isRefreshing: isRefreshingAppleStatus
			)
		]
	}

	private func _buildMetadataPills(from cert: CertificatePair) -> [NBPillItem] {
		var pills: [NBPillItem] = []

		if cert.ppQCheck == true {
			pills.append(NBPillItem(title: .localized("PPQCheck"), icon: "checkmark.shield", color: .red))
		}

		if let info = cert.expiration?.expirationInfo() {
			pills.append(NBPillItem(
				title: info.formatted,
				icon: info.icon,
				color: info.color
			))
		}
		
		return pills
	}

	private func _statusPill(title: String, status: CertificateStatusValue, isRefreshing: Bool) -> NBPillItem {
		return NBPillItem(
			title: title,
			icon: isRefreshing ? "arrow.clockwise" : status.icon,
			color: isRefreshing ? .secondary : status.color
		)
	}
}
