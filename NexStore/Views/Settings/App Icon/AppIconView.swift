//
//  AppIconView.swift
//  Feather
//
//  Created by samara on 19.06.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View extension: Model
extension AppIconView {
	struct AltIcon: Identifiable {
		var displayName: String
		var author: String
		var key: String?
		var fileName: String
		var image: UIImage
		var id: String { key ?? displayName }
		
		init(displayName: String, author: String, key: String? = nil, fileName: String? = nil) {
			self.displayName = displayName
			self.author = author
			self.key = key
			self.fileName = fileName ?? key ?? "Icon"
			self.image = altImage(self.fileName)
		}
	}
	
	static func altImage(_ name: String) -> UIImage {
		let candidates: [URL?] = [
			Bundle.main.url(forResource: "\(name)@2x", withExtension: "png", subdirectory: "Icons/Main"),
			Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons/Main"),
			Bundle.main.url(forResource: "\(name)@2x", withExtension: "png"),
			Bundle.main.url(forResource: name, withExtension: "png")
		]
		
		for url in candidates.compactMap({ $0 }) {
			if let image = UIImage(contentsOfFile: url.path) {
				return image
			}
		}
		
		return UIImage()
	}
}

// MARK: - View
struct AppIconView: View {
	@Binding var currentIcon: String?
	
	// dont translate
	var sections: [String: [AltIcon]] = [
		"Main": [
			AltIcon(displayName: "NexStore", author: "Samara", key: nil, fileName: "Icon"),
			AltIcon(displayName: "NexStore (macOS)", author: "Samara", key: "Mac", fileName: "Mac"),
			AltIcon(displayName: "NexStore Donor", author: "Samara", key: "Donor", fileName: "Donor")
		]
	]
	
	// MARK: Body
	var body: some View {
		NBList(.localized("App Icon")) {
			ForEach(sections.keys.sorted(), id: \.self) { section in
				if let icons = sections[section] {
					NBSection(section) {
						ForEach(icons) { icon in
							_icon(icon: icon)
						}
					}
				}
			}
		}
		.onAppear {
			currentIcon = UIApplication.shared.alternateIconName
		}
	}
}

// MARK: - View extension
extension AppIconView {
	@ViewBuilder
	private func _icon(
		icon: AppIconView.AltIcon
	) -> some View {
		Button {
			UIApplication.shared.setAlternateIconName(icon.key) { _ in
				currentIcon = UIApplication.shared.alternateIconName
			}
		} label: {
			HStack(spacing: 18) {
				Image(uiImage: icon.image)
					.appIconStyle()
				
				NBTitleWithSubtitleView(
					title: icon.displayName,
					subtitle: icon.author,
					linelimit: 0
				)
				
				if currentIcon == icon.key {
					Image(systemName: "checkmark").bold()
				}
			}
		}
	}
}
