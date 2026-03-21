import Foundation

/// Searches the web. Uses Perplexity AI when an API key is configured (grounded, cited answers).
/// Falls back to DuckDuckGo Instant Answer API (no API key needed) otherwise.
struct WebSearchTool: NativeTool {
    let name = "web_search"
    let description = "Search the web for information. Uses Perplexity AI (with citations) when configured, otherwise DuckDuckGo. Returns a brief summary."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "The search query"
            ]
        ],
        "required": ["query"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "No search query provided."
        }

        // Try Perplexity first if configured
        if Config.isPerplexityConfigured {
            let result = await searchPerplexity(query: query)
            if let result = result {
                return result
            }
            // Fall through to DuckDuckGo on failure
        }

        return await searchDuckDuckGo(query: query)
    }

    // MARK: - Perplexity Search

    private func searchPerplexity(query: String) async -> String? {
        guard let url = URL(string: "https://api.perplexity.ai/chat/completions") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Config.perplexityAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "sonar",
            "messages": [
                ["role": "user", "content": query]
            ],
            "max_tokens": 400,
            "return_citations": true
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("🔍 Perplexity failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)), falling back to DuckDuckGo")
                return nil // Fall back to DuckDuckGo
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }

            var result = content
            if let citations = json["citations"] as? [String], !citations.isEmpty {
                let sourceList = citations.prefix(3).enumerated().map { "[\($0.offset + 1)] \($0.element)" }
                result += "\n\nSources: \(sourceList.joined(separator: ", "))"
            }

            return "Search result for \"\(query)\" (via Perplexity): \(result)"

        } catch {
            print("🔍 Perplexity error: \(error.localizedDescription), falling back to DuckDuckGo")
            return nil
        }
    }

    // MARK: - DuckDuckGo Fallback

    private func searchDuckDuckGo(query: String) async -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return "Couldn't build search URL."
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "Search service is temporarily unavailable."
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Couldn't parse search results."
            }

            // Try direct answer first
            if let answer = json["Answer"] as? String, !answer.isEmpty {
                return "Search result for \"\(query)\": \(answer)"
            }

            // Try abstract
            if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
                let source = json["AbstractSource"] as? String ?? ""
                let sourceStr = source.isEmpty ? "" : " (via \(source))"
                return "Search result for \"\(query)\": \(abstract)\(sourceStr)"
            }

            // Try related topics
            if let topics = json["RelatedTopics"] as? [[String: Any]], !topics.isEmpty {
                let summaries = topics.prefix(3).compactMap { topic -> String? in
                    topic["Text"] as? String
                }
                if !summaries.isEmpty {
                    return "Search results for \"\(query)\": \(summaries.joined(separator: ". "))"
                }
            }

            return "I searched for \"\(query)\" but didn't find a clear answer. The LLM should try answering from its own knowledge."

        } catch {
            return "Search failed: \(error.localizedDescription)"
        }
    }
}
