//
//  NovaDNSDynamic.swift
//  NexStore
//
//  Created by NovaDev404 on 24.02.2026.
//

import Foundation

@MainActor
public enum NovaDNSDynamic {
    public static func sendRequest(endpoint: String) async {
        guard let url = URL(string: "https://api.novadev.vip/api/novadns-dynamic/\(endpoint)") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: request)
    }
}
