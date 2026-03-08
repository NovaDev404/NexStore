//
//  NovaCerts.swift
//  NexStore
//
//  Created by NovaDev404 on 07.03.2026.
//

import Foundation

enum NovaCerts {
	static let readmeURL = URL(string: "https://raw.githubusercontent.com/NovaDev404/NovaCerts/refs/heads/main/README.md")!
	private static let _rawBaseURL = "https://github.com/NovaDev404/NovaCerts/raw/refs/heads/main"
	private static let _pathComponentAllowedCharacters: CharacterSet = {
		var allowedCharacters = CharacterSet.urlPathAllowed
		allowedCharacters.remove(charactersIn: "/")
		return allowedCharacters
	}()

	struct CatalogItem: Identifiable, Hashable {
		let id: String
		let name: String
		let certificateType: String
		let status: Status
		let rawStatusText: String
		let validFrom: String
		let validTo: String
		fileprivate let order: Int

		var subtitle: String {
			var components = [certificateType]
			if !validTo.isEmpty {
				components.append(String.localized("Valid To: %@", arguments: validTo))
			}
			return components.joined(separator: " • ")
		}

		var groupingBaseName: String? {
			guard let range = name.range(of: #"\s+\([^()]+\)$"#, options: .regularExpression) else {
				return nil
			}

			let baseName = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
			return baseName.isEmpty ? nil : baseName
		}

		var p12URL: URL {
			_assetURL(fileName: "\(name).p12")
		}

		var provisionURL: URL {
			_assetURL(fileName: "\(name).mobileprovision")
		}

		var passwordURL: URL {
			_assetURL(fileName: "password.txt")
		}

		private func _assetURL(fileName: String) -> URL {
			let encodedFolder = NovaCerts._encodePathComponent(name)
			let encodedFileName = NovaCerts._encodePathComponent(fileName)
			return URL(string: "\(NovaCerts._rawBaseURL)/\(encodedFolder)/\(encodedFileName)")!
		}
	}

	struct CatalogSection: Identifiable, Hashable {
		let id: String
		let title: String
		let subtitle: String?
		let status: Status
		let certificates: [CatalogItem]

		var isGroup: Bool {
			certificates.count > 1
		}
	}

	enum Status: String, Hashable {
		case signed
		case revoked
		case unknown

		init(markdownValue: String) {
			let normalizedValue = markdownValue.lowercased()
			if normalizedValue.contains("signed") {
				self = .signed
			} else if normalizedValue.contains("revoked") {
				self = .revoked
			} else {
				self = .unknown
			}
		}

		var title: String {
			switch self {
			case .signed:
				String.localized("Signed")
			case .revoked:
				String.localized("Revoked")
			case .unknown:
				String.localized("Unknown")
			}
		}

		static func aggregate(_ statuses: [Status]) -> Status {
			if statuses.contains(.signed) {
				return .signed
			}

			if statuses.contains(.unknown) {
				return .unknown
			}

			return .revoked
		}
	}

	enum NovaCertsError: LocalizedError {
		case invalidResponse(URL)
		case invalidReadmeData
		case emptyCatalog
		case invalidPassword

		var errorDescription: String? {
			switch self {
			case .invalidResponse(let url):
				String.localized("Failed to fetch %@.", arguments: url.absoluteString)
			case .invalidReadmeData:
				String.localized("The NovaCerts README could not be parsed.")
			case .emptyCatalog:
				String.localized("NovaCerts did not return any certificates.")
			case .invalidPassword:
				String.localized("The downloaded NovaCert certificate password is invalid.")
			}
		}
	}
}

// MARK: - Catalog
extension NovaCerts {
	static func fetchCatalog() async throws -> [CatalogSection] {
		let markdown = try await _downloadText(from: readmeURL)
		let entries = _parseCatalog(from: markdown)

		guard !entries.isEmpty else {
			throw NovaCertsError.emptyCatalog
		}

		return _buildSections(from: entries)
	}

	private static func _parseCatalog(from markdown: String) -> [CatalogItem] {
		let lines = markdown.components(separatedBy: .newlines)
		var entries: [CatalogItem] = []

		for line in lines {
			let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
			guard trimmedLine.hasPrefix("|"), trimmedLine.hasSuffix("|") else {
				continue
			}

			if trimmedLine.contains("| Company | Type | Status | Valid From | Valid To | Download |") || trimmedLine.contains("|:--------|") {
				continue
			}

			let rawColumns = trimmedLine
				.split(separator: "|", omittingEmptySubsequences: false)
				.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

			guard rawColumns.count >= 8 else {
				continue
			}

			let columns = Array(rawColumns.dropFirst().dropLast())
			guard columns.count >= 6 else {
				continue
			}

			let company = columns[0]
			let type = columns[1]
			let statusText = columns[2]
			let validFrom = columns[3]
			let validTo = columns[4]

			guard !company.isEmpty else {
				continue
			}

			entries.append(
				CatalogItem(
					id: "\(entries.count)-\(company)",
					name: company,
					certificateType: type,
					status: Status(markdownValue: statusText),
					rawStatusText: statusText,
					validFrom: validFrom,
					validTo: validTo,
					order: entries.count
				)
			)
		}

		return entries
	}

	private static func _buildSections(from entries: [CatalogItem]) -> [CatalogSection] {
		var groupedEntries: [String: [CatalogItem]] = [:]

		for entry in entries {
			guard let baseName = entry.groupingBaseName else {
				continue
			}

			groupedEntries[baseName, default: []].append(entry)
		}

		var renderedGroups = Set<String>()
		var sections: [CatalogSection] = []

		for entry in entries {
			if let baseName = entry.groupingBaseName,
			   let bucket = groupedEntries[baseName],
			   bucket.count > 1 {
				guard renderedGroups.insert(baseName).inserted else {
					continue
				}

				let sortedBucket = bucket.sorted { $0.order < $1.order }
				sections.append(
					CatalogSection(
						id: "group-\(baseName)",
						title: String.localized("%@ - %lld Versions", arguments: baseName, Int64(sortedBucket.count)),
						subtitle: String.localized("%lld versions available", arguments: Int64(sortedBucket.count)),
						status: Status.aggregate(sortedBucket.map(\.status)),
						certificates: sortedBucket
					)
				)
			} else {
				sections.append(
					CatalogSection(
						id: "single-\(entry.id)",
						title: entry.name,
						subtitle: entry.subtitle,
						status: entry.status,
						certificates: [entry]
					)
				)
			}
		}

		return sections
	}
}

// MARK: - Import
extension NovaCerts {
	static func importCertificate(_ certificate: CatalogItem) async throws {
		let fileManager = FileManager.default
		let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent("NovaCerts_\(UUID().uuidString)", isDirectory: true)

		try fileManager.createDirectoryIfNeeded(at: temporaryDirectory)

		do {
			async let p12Contents = _downloadData(from: certificate.p12URL)
			async let provisionContents = _downloadData(from: certificate.provisionURL)
			async let passwordContents = _downloadText(from: certificate.passwordURL)

			let p12URL = temporaryDirectory.appendingPathComponent("certificate.p12")
			let provisionURL = temporaryDirectory.appendingPathComponent("certificate.mobileprovision")
			let p12Data = try await p12Contents
			let provisionData = try await provisionContents
			let passwordText = try await passwordContents

			try p12Data.write(to: p12URL, options: .atomic)
			try provisionData.write(to: provisionURL, options: .atomic)

			let password = passwordText.trimmingCharacters(in: .whitespacesAndNewlines)

			guard FR.checkPasswordForCertificate(for: p12URL, with: password, using: provisionURL) else {
				throw NovaCertsError.invalidPassword
			}

			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				FR.handleCertificateFiles(
					p12URL: p12URL,
					provisionURL: provisionURL,
					p12Password: password,
					certificateName: certificate.name
				) { error in
					try? fileManager.removeFileIfNeeded(at: temporaryDirectory)

					if let error {
						continuation.resume(throwing: error)
					} else {
						continuation.resume(returning: ())
					}
				}
			}
		} catch {
			try? fileManager.removeFileIfNeeded(at: temporaryDirectory)
			throw error
		}
	}
}

// MARK: - Networking
extension NovaCerts {
	private static func _downloadData(from url: URL) async throws -> Data {
		var request = URLRequest(url: url)
		request.timeoutInterval = 30
		request.setValue("NexStore/1.0", forHTTPHeaderField: "User-Agent")

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
			throw NovaCertsError.invalidResponse(url)
		}

		return data
	}

	private static func _downloadText(from url: URL) async throws -> String {
		let data = try await _downloadData(from: url)
		guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
			throw NovaCertsError.invalidReadmeData
		}

		return text
	}
}

// MARK: - Helpers
extension NovaCerts {
	private static func _encodePathComponent(_ value: String) -> String {
		value.addingPercentEncoding(withAllowedCharacters: _pathComponentAllowedCharacters) ?? value
	}
}