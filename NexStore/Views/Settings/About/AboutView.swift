//
//  AboutView.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - Extension: Model
extension AboutView {
	enum CreditsGroup: String, Codable, Hashable {
		case nexstore
		case feather
	}

	struct CreditsModel: Codable, Hashable {
		let name: String?
		let desc: String?
		let github: String
		let group: CreditsGroup
	}
}

// MARK: - View
struct AboutView: View {
	@State private var _credits: [CreditsModel] = []
	@State private var _isFeatherDevelopersExpanded = false
	@State var isLoading = true

	private let _fixedCredits: [CreditsModel] = [
		.init(name: "NovaDev404", desc: "Developer", github: "NovaDev404", group: .nexstore),
		.init(name: "Samara", desc: "Developer", github: "claration", group: .feather),
		.init(name: "Nyasami", desc: "Contributor", github: "Nyasami", group: .feather),
		.init(name: "Adrian Castro", desc: "Contributor", github: "castdrian", group: .feather),
		.init(name: "Lakhan Lothiyi", desc: "Repositories", github: "llsc12", group: .feather),
		.init(name: "HAHALOSAH", desc: "Operations", github: "HAHALOSAH", group: .feather),
		.init(name: "Jackson Coxson", desc: "Idevice", github: "jkcoxson", group: .feather)
		// Add more NexStore developers with `group: .nexstore`.
	]
	
	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			if !isLoading {
				Section {
					VStack {
						FRAppIconView(size: 72)
						
						Text(Bundle.main.exec)
							.font(.largeTitle)
							.bold()
							.foregroundStyle(Color.accentColor)
						
						HStack(spacing: 4) {
							Text(.localized("Version"))
							Text(Bundle.main.version)
						}
						.font(.footnote)
						.foregroundStyle(.secondary)
					}
				}
				.frame(maxWidth: .infinity)
				.listRowBackground(EmptyView())
				
				NBSection(.localized("Credits")) {
					ForEach(_nexStoreDevelopers, id: \.github) { credit in
						_credit(name: credit.name, desc: credit.desc, github: credit.github)
					}
					
					if !_featherDevelopers.isEmpty {
						DisclosureGroup(isExpanded: $_isFeatherDevelopersExpanded) {
							ForEach(_featherDevelopers, id: \.github) { credit in
								_credit(name: credit.name, desc: credit.desc, github: credit.github)
							}
						} label: {
							_featherDevelopersHeader
						}
					}
					.transition(.slide)
				}
				
			}
		}
		.animation(.default, value: isLoading)
		.task {
			await _fetchAllData()
		}
	}
	
	private func _fetchAllData() async {
		await MainActor.run {
			self._credits = self._fixedCredits
		}
		
		await MainActor.run {
			isLoading = false
		}
	}
	
	private var _nexStoreDevelopers: [CreditsModel] {
		_credits.filter { $0.group == .nexstore }
	}
	
	private var _featherDevelopers: [CreditsModel] {
		_credits.filter { $0.group == .feather }
	}
}

// MARK: - Extension: view
extension AboutView {
	private var _featherDevelopersHeader: some View {
		HStack(spacing: 10) {
			Text("Feather Developers")
			Spacer()
			_overlappingContributorIcons(_featherDevelopers)
		}
	}
	
	private func _overlappingContributorIcons(_ credits: [CreditsModel]) -> some View {
		let visibleCredits = Array(credits.prefix(5))
		
		return HStack(spacing: -10) {
			ForEach(Array(visibleCredits.enumerated()), id: \.element.github) { index, credit in
				AsyncImage(url: URL(string: "https://github.com/\(credit.github).png")) { phase in
					switch phase {
					case let .success(image):
						image
							.resizable()
							.scaledToFill()
					case .failure:
						Circle()
							.fill(.secondary.opacity(0.2))
					case .empty:
						Circle()
							.fill(.secondary.opacity(0.15))
					@unknown default:
						Circle()
							.fill(.secondary.opacity(0.15))
					}
				}
				.frame(width: 24, height: 24)
				.clipShape(Circle())
				.overlay {
					Circle()
						.stroke(Color(.systemBackground), lineWidth: 2)
				}
				.zIndex(Double(visibleCredits.count - index))
			}
			
			if credits.count > visibleCredits.count {
				Text("+\(credits.count - visibleCredits.count)")
					.font(.caption2)
					.foregroundStyle(.secondary)
					.padding(.leading, 12)
			}
		}
	}
	
	@ViewBuilder
	private func _credit(
		name: String?,
		desc: String?,
		github: String
	) -> some View {
		Button {
			UIApplication.open("https://github.com/\(github)")
		} label: {
			HStack {
				FRIconCellView(
					title: name ?? github,
					subtitle: desc ?? "",
					iconUrl: URL(string: "https://github.com/\(github).png")!,
					size: 45,
					isCircle: true
				)
				
				Image(systemName: "arrow.up.right")
					.foregroundColor(.secondary.opacity(0.65))
			}
		}
	}
}
