//
//  CertificatesView.swift
//  Feather
//
//  Created by samara on 15.04.2025.
//

import SwiftUI
import NimbleViews

private enum CertificateAddSheet: String, Identifiable {
	case certificateFiles
	case official

	var id: String { rawValue }
}

// MARK: - View
struct CertificatesView: View {
	@AppStorage("nexstore.selectedCert") private var _storedSelectedCert: Int = 0
	
	@State private var _addSheet: CertificateAddSheet?
	@State private var _isSelectedInfoPresenting: CertificatePair?

	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>
	
	//
	private var _bindingSelectedCert: Binding<Int>?
	private var _selectedCertBinding: Binding<Int> {
		_bindingSelectedCert ?? $_storedSelectedCert
	}
	
	init(selectedCert: Binding<Int>? = nil) {
		self._bindingSelectedCert = selectedCert
	}
	
	// MARK: Body
	var body: some View {
		NBGrid {
			ForEach(Array(_certificates.enumerated()), id: \.element.uuid) { index, cert in
				_cellButton(for: cert, at: index)
			}
		}
		.navigationTitle(.localized("Certificates"))
		.overlay {
			if _certificates.isEmpty {
				if #available(iOS 17, *) {
					ContentUnavailableView {
						Label(.localized("No Certificates"), systemImage: "questionmark.folder.fill")
					} description: {
						Text(.localized("Get started signing by importing your first certificate."))
					} actions: {
						Menu {
							_addOptions()
						} label: {
							NBButton(.localized("Import"), style: .text)
						}
					}
				}
			}
		}
		.toolbar {
			if _bindingSelectedCert == nil {
				NBToolbarMenu(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing
				) {
					_addOptions()
				}
			}
		}
		.sheet(item: $_isSelectedInfoPresenting) { cert in
			CertificatesInfoView(cert: cert)
		}
		.sheet(item: $_addSheet) { sheet in
			_addSheetView(for: sheet)
		}
	}
}

// MARK: - View extension
extension CertificatesView {
	@ViewBuilder
	private func _addOptions() -> some View {
		Button(.localized("Official (NovaCerts)")) {
			_addSheet = .official
		}

		Button(.localized("Certificate Files")) {
			_addSheet = .certificateFiles
		}
	}

	@ViewBuilder
	private func _addSheetView(for sheet: CertificateAddSheet) -> some View {
		switch sheet {
		case .certificateFiles:
			CertificatesAddView()
				.presentationDetents([.medium])
		case .official:
			OfficialCertificatesView()
				.presentationDetents([.large])
		}
	}

	@ViewBuilder
	private func _cellButton(for cert: CertificatePair, at index: Int) -> some View {
		let cornerRadius = {
			if #available(iOS 26.0, *) {
				28.0
			} else {
				10.5
			}
		}()
		
		Button {
			_selectedCertBinding.wrappedValue = index
		} label: {
			CertificatesCellView(
				cert: cert
			)
			.padding()
			.background(
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(Color(uiColor: .quaternarySystemFill))
			)
			.overlay(
				RoundedRectangle(cornerRadius: cornerRadius)
					.strokeBorder(
						_selectedCertBinding.wrappedValue == index ? Color.accentColor : Color.clear,
						lineWidth: 2
					)
			)
			.contextMenu {
				_contextActions(for: cert)
				if cert.isDefault != true {
					Divider()
					_actions(for: cert)
				}
			}
			.transaction {
				$0.animation = nil
			}
		}
		.buttonStyle(.plain)
	}
	
	@ViewBuilder
	private func _actions(for cert: CertificatePair) -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			Storage.shared.deleteCertificate(for: cert)
		}
	}
	
	@ViewBuilder
	private func _contextActions(for cert: CertificatePair) -> some View {
		Button(.localized("Get Info"), systemImage: "info.circle") {
			_isSelectedInfoPresenting = cert
		}
		Divider()
		Button(.localized("Refresh Status"), systemImage: "arrow.clockwise") {
			CertificateStatusManager.shared.refreshStatus(for: cert)
		}
	}
}
