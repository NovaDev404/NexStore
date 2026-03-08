//
//  OfficialCertificatesView.swift
//  NexStore
//
//  Created by NovaDev404 on 07.03.2026.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct OfficialCertificatesView: View {
	@Environment(\.dismiss) private var dismiss

	@State private var _catalogSections: [NovaCerts.CatalogSection] = []
	@State private var _expandedGroups: Set<String> = []
	@State private var _errorMessage: String?
	@State private var _hasLoaded = false
	@State private var _isImporting = false
	@State private var _isLoading = false
	@State private var _importingCertificateID: String?

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Official Certificates"), displayMode: .inline) {
			Group {
				if _isLoading || !_hasLoaded {
					_loadingView
				} else if let errorMessage = _errorMessage {
					_errorView(message: errorMessage)
				} else {
					_catalogList
				}
			}
			.animation(.default, value: _catalogSections.map(\.id))
			.animation(.default, value: _isLoading)
			.toolbar {
				NBToolbarButton(role: .cancel)

				if _isImporting {
					ToolbarItem(placement: .confirmationAction) {
						ProgressView()
					}
				}
			}
			.task {
				guard !_hasLoaded else { return }
				await _loadCatalog()
			}
		}
	}
}

// MARK: - Content
extension OfficialCertificatesView {
	private var _catalogList: some View {
		List {
			Section {
				ForEach(_catalogSections) { section in
					if section.isGroup {
						_groupRow(section)
					} else if let certificate = section.certificates.first {
						_certificateButton(certificate)
					}
				}
			} footer: {
				Text(.localized("Certificates are fetched from the NovaCerts README and imported directly into NexStore."))
			}
		}
		.listStyle(.insetGrouped)
		.disabled(_isImporting)
		.refreshable {
			await _loadCatalog(force: true)
		}
	}

	private var _loadingView: some View {
		VStack(spacing: 12) {
			ProgressView()
			Text(.localized("Fetching NovaCerts..."))
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}

	private func _errorView(message: String) -> some View {
		VStack(spacing: 14) {
			Image(systemName: "exclamationmark.triangle")
				.font(.largeTitle)
				.foregroundStyle(.orange)

			Text(.localized("Couldn't Load NovaCerts"))
				.font(.headline)

			Text(message)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			Button(.localized("Retry")) {
				Task {
					await _loadCatalog(force: true)
				}
			}
			.buttonStyle(.borderedProminent)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}
}

// MARK: - Rows
extension OfficialCertificatesView {
	@ViewBuilder
	private func _groupRow(_ section: NovaCerts.CatalogSection) -> some View {
		DisclosureGroup(isExpanded: _groupExpansionBinding(for: section.id)) {
			ForEach(section.certificates) { certificate in
				_certificateButton(certificate)
			}
		} label: {
			_rowContent(
				title: section.title,
				subtitle: section.subtitle,
				statusText: section.status.title,
				status: section.status,
				isImporting: false
			)
		}
	}

	@ViewBuilder
	private func _certificateButton(_ certificate: NovaCerts.CatalogItem) -> some View {
		Button {
			Task {
				await _import(certificate)
			}
		} label: {
			_rowContent(
				title: certificate.name,
				subtitle: certificate.subtitle,
				statusText: certificate.status.title,
				status: certificate.status,
				isImporting: _importingCertificateID == certificate.id
			)
		}
		.buttonStyle(.plain)
		.disabled(_isImporting)
	}

	private func _rowContent(
		title: String,
		subtitle: String?,
		statusText: String,
		status: NovaCerts.Status,
		isImporting: Bool
	) -> some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.body.weight(.medium))
					.foregroundStyle(.primary)
					.multilineTextAlignment(.leading)

				if let subtitle, !subtitle.isEmpty {
					Text(subtitle)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.leading)
				}
			}

			Spacer(minLength: 12)

			if isImporting {
				ProgressView()
			} else {
				_statusBadge(text: statusText, status: status)
			}
		}
		.contentShape(Rectangle())
	}

	private func _statusBadge(text: String, status: NovaCerts.Status) -> some View {
		let color = _statusColor(for: status)

		return Text(text)
			.font(.footnote.weight(.semibold))
			.foregroundStyle(color)
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(color.opacity(0.12), in: Capsule())
	}

	private func _statusColor(for status: NovaCerts.Status) -> Color {
		switch status {
		case .signed:
			return .green
		case .revoked:
			return .red
		case .unknown:
			return .secondary
		}
	}

}

// MARK: - Actions
extension OfficialCertificatesView {
	@MainActor
	private func _loadCatalog(force: Bool = false) async {
		if _isLoading && !force {
			return
		}

		_isLoading = true
		_errorMessage = nil

		defer {
			_hasLoaded = true
			_isLoading = false
		}

		do {
			_catalogSections = try await NovaCerts.fetchCatalog()
			_expandedGroups = []
		} catch {
			_catalogSections = []
			_errorMessage = error.localizedDescription
		}
	}

	@MainActor
	private func _import(_ certificate: NovaCerts.CatalogItem) async {
		guard !_isImporting else { return }

		_isImporting = true
		_importingCertificateID = certificate.id

		defer {
			_importingCertificateID = nil
			_isImporting = false
		}

		do {
			try await NovaCerts.importCertificate(certificate)
			dismiss()
		} catch {
			UIAlertController.showAlertWithOk(
				title: .localized("Error"),
				message: error.localizedDescription
			)
		}
	}

	private func _groupExpansionBinding(for id: String) -> Binding<Bool> {
		Binding {
			_expandedGroups.contains(id)
		} set: { isExpanded in
			if isExpanded {
				_expandedGroups.insert(id)
			} else {
				_expandedGroups.remove(id)
			}
		}
	}
}