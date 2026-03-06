//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON

// MARK: - Class
@MainActor
final class SourcesViewModel: ObservableObject {
    static let shared = SourcesViewModel()
    
    typealias RepositoryDataHandler = Result<ASRepository, Error>
    
    private let _dataService = NBFetchService()
    
    var isFinished = true
    @Published var sources: [AltSource: ASRepository] = [:]
    
    func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
        guard isFinished else { return }
        
        // check if sources to be fetched are the same as before, if yes, return
        // also skip check if refresh is true
        if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { return }
        
        // isfinished is used to prevent multiple fetches at the same time
        isFinished = false
        defer { isFinished = true }
        
        await MainActor.run {
            self.sources = [:]
        }
        
        let sourcesArray = Array(sources)

        for startIndex in stride(from: 0, to: sourcesArray.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, sourcesArray.count)
            let batch = sourcesArray[startIndex..<endIndex]

            // Prepare Sendable value types for concurrent work
            let items: [(key: UUID, url: URL?)] = batch.map { source in
                return (UUID(), source.sourceURL)
            }

            // Map UUIDs back to AltSource on the main actor after work completes
            var keyToSource: [UUID: AltSource] = [:]
            for (index, source) in batch.enumerated() {
                keyToSource[items[index].key] = source
            }

            let batchResults = await withTaskGroup(of: (UUID, ASRepository?).self, returning: [UUID: ASRepository].self) { group in
                for item in items {
                    group.addTask {
                        guard let url = item.url else { return (item.key, nil) }
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            let repo = try JSONDecoder().decode(ASRepository.self, from: data)
                            return (item.key, repo)
                        } catch {
                            return (item.key, nil)
                        }
                    }
                }

                var results = [UUID: ASRepository]()
                for await (key, repo) in group {
                    if let repo {
                        results[key] = repo
                    }
                }
                return results
            }

            await MainActor.run {
                for (key, repo) in batchResults {
                    if let source = keyToSource[key] {
                        self.sources[source] = repo
                    }
                }
            }
        }
    }
}
