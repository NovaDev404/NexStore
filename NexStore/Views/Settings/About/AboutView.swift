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

	struct CreditsModel: Codable, Hashable, Identifiable {
		let name: String?
		let desc: String?
		let github: String?
		let reddit: String?
		let group: CreditsGroup

		init(
			name: String?,
			desc: String?,
			github: String? = nil,
			reddit: String? = nil,
			group: CreditsGroup
		) {
			self.name = name
			self.desc = desc
			self.github = github
			self.reddit = reddit
			self.group = group
		}

		var id: String {
			if let github, !github.isEmpty {
				return "github:\(github.lowercased())"
			}

			if let reddit, !reddit.isEmpty {
				return "reddit:\(reddit.lowercased())"
			}

			return "\(group.rawValue)-\(name ?? "unknown")-\(desc ?? "unknown")"
		}

		var profileURL: String? {
			if let github, !github.isEmpty {
				return "https://github.com/\(github)"
			}

			if let reddit, !reddit.isEmpty {
				return "https://www.reddit.com/user/\(reddit)"
			}

			return nil
		}

		var avatarURL: URL {
			if let github, !github.isEmpty {
				return URL(string: "https://github.com/\(github).png")!
			}

			return URL(string: "https://www.redditstatic.com/avatars/defaults/v2/avatar_default_1.png")!
		}

		var displayHandle: String {
			if let github, !github.isEmpty {
				return github
			}

			if let reddit, !reddit.isEmpty {
				return "u/\(reddit)"
			}

			return "Unknown"
		}
	}
}

// MARK: - View
struct AboutView: View {
	@State private var _credits: [CreditsModel] = []
	@State private var _redditAvatarURLs: [String: URL] = [:]
	@State private var _isFeatherDevelopersExpanded = false
	@State var isLoading = true

	private let _fixedCredits: [CreditsModel] = [
		.init(name: "NovaDev404", desc: "Developer", github: "NovaDev404", group: .nexstore),
		.init(name: "Beckett R", desc: "NexStore Icon", reddit: "GoblinsStoleMyMac", group: .nexstore),
		.init(name: "Samara", desc: "Developer", github: "claration", group: .feather),
		.init(name: "Nyasami", desc: "Contributor", github: "Nyasami", group: .feather),
		.init(name: "Adrian Castro", desc: "Contributor", github: "castdrian", group: .feather),
		.init(name: "Lakhan Lothiyi", desc: "Repositories", github: "llsc12", group: .feather),
		.init(name: "HAHALOSAH", desc: "Operations", github: "HAHALOSAH", group: .feather),
		.init(name: "Jackson Coxson", desc: "Idevice", github: "jkcoxson", group: .feather)
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
					ForEach(_nexStoreDevelopers) { credit in
						_credit(credit)
					}
					
					if !_featherDevelopers.isEmpty {
						DisclosureGroup(isExpanded: $_isFeatherDevelopersExpanded) {
							ForEach(_featherDevelopers) { credit in
								_credit(credit)
							}
						} label: {
							_featherDevelopersHeader
						}
						.transition(.slide)
					}
				}
				
			}
		}
		.animation(.default, value: isLoading)
		.task {
			await _fetchAllData()
			await _fetchRedditAvatars()
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

	private func _fetchRedditAvatars() async {
		let usernames = Set<String>(
			_credits.compactMap { credit in
				guard let reddit = credit.reddit?.trimmingCharacters(in: .whitespacesAndNewlines), !reddit.isEmpty else {
					return nil
				}

				return reddit
			}
		)

		guard !usernames.isEmpty else {
			return
		}

		await withTaskGroup(of: (String, URL?).self) { group in
			for username in usernames {
				group.addTask {
					let avatarURL = await self._fetchRedditAvatarURL(username: username)
					return (username.lowercased(), avatarURL)
				}
			}

			var resolvedAvatars: [String: URL] = [:]

			for await (username, avatarURL) in group {
				if let avatarURL {
					resolvedAvatars[username] = avatarURL
				}
			}

			await MainActor.run {
				_redditAvatarURLs.merge(resolvedAvatars) { _, new in new }
			}
		}
	}

	private func _fetchRedditAvatarURL(username: String) async -> URL? {
		guard let aboutURL = URL(string: "https://www.reddit.com/user/\(username)/about.json") else {
			return nil
		}

		var request = URLRequest(url: aboutURL)
		request.setValue("NexStore/1.0", forHTTPHeaderField: "User-Agent")
		request.timeoutInterval = 15

		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
				return nil
			}

			let payload = try JSONDecoder().decode(RedditAboutResponse.self, from: data)

			let iconString: String?
			if let iconImg = payload.data.iconImg, !iconImg.isEmpty {
				iconString = iconImg
			} else if let snoovatarImg = payload.data.snoovatarImg, !snoovatarImg.isEmpty {
				iconString = snoovatarImg
			} else {
				iconString = nil
			}

			guard let iconString else {
				return nil
			}

			let normalizedURL = iconString.replacingOccurrences(of: "&amp;", with: "&")
			return URL(string: normalizedURL)
		} catch {
			return nil
		}
	}

	private struct RedditAboutResponse: Decodable {
		let data: RedditUserData

		struct RedditUserData: Decodable {
			let iconImg: String?
			let snoovatarImg: String?

			enum CodingKeys: String, CodingKey {
				case iconImg = "icon_img"
				case snoovatarImg = "snoovatar_img"
			}
		}
	}
}

// MARK: - Extension: view
extension AboutView {
	private func _avatarURL(for credit: CreditsModel) -> URL {
		if let reddit = credit.reddit?.lowercased(), let redditAvatarURL = _redditAvatarURLs[reddit] {
			return redditAvatarURL
		}

		return credit.avatarURL
	}

	private var _featherDevelopersHeader: some View {
		HStack(spacing: 10) {
			Text("Feather Developers")
			Spacer()
			_overlappingContributorIcons(_featherDevelopers)
		}
	}
	
	private func _overlappingContributorIcons(_ credits: [CreditsModel]) -> some View {
		let visibleCredits = Array(credits.prefix(6))
		
		return HStack(spacing: -10) {
			ForEach(Array(visibleCredits.enumerated()), id: \.element.id) { index, credit in
				AsyncImage(url: _avatarURL(for: credit)) { phase in
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
	
	private func _credit(_ credit: CreditsModel) -> some View {
		Button {
			guard let profileURL = credit.profileURL else {
				return
			}

			UIApplication.open(profileURL)
		} label: {
			HStack {
				FRIconCellView(
					title: credit.name ?? credit.displayHandle,
					subtitle: credit.desc ?? "",
					iconUrl: _avatarURL(for: credit),
					size: 45,
					isCircle: true
				)
				
				Image(systemName: "arrow.up.right")
					.foregroundColor(.secondary.opacity(0.65))
			}
		}
	}
}
