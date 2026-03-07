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
			}
		}
	}
}