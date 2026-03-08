//
//  StatusViewModel.swift
//  Feather
//
//  Created by samara on 24.04.2025.
//

import Foundation
import Combine
import IDeviceSwift

extension String {
	var localized: String { NSLocalizedString(self, comment: "") }
}

extension InstallerStatusViewModel {
	static var enablingPPQStatus: Any {
		struct EnablingPPQ: Equatable {}
		return EnablingPPQ()
	}

	var statusImage: String {
		if String(describing: status) == String(describing: InstallerStatusViewModel.enablingPPQStatus) {
			return "bolt.horizontal.fill"
		}
		switch status {
		case .none:
			return "archivebox.fill"
		case .ready:
			return "app.gift"
		case .sendingManifest, .sendingPayload:
			return "paperplane.fill"
		case .installing:
			return "square.and.arrow.down"
		case .completed:
			return "app.badge.checkmark"
		case .broken:
			return "exclamationmark.triangle.fill"
		default:
			return "archivebox.fill"
		}
	}

	var statusLabel: String {
		if String(describing: status) == String(describing: InstallerStatusViewModel.enablingPPQStatus) {
			return "Enabling PPQ".localized
		}
		switch status {
		case .none:
			return "Packaging".localized
		case .ready:
			return "Ready".localized
		case .sendingManifest:
			return "Sending Manifest".localized
		case .sendingPayload:
			return "Sending Payload".localized
		case .installing:
			return "Installing".localized
		case .completed:
			return "Completed".localized
		case .broken:
			return "Error".localized
		default:
			return "Packaging".localized
		}
	}
}
