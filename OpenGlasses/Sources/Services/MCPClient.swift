import Foundation

/// Lightweight MCP (Model Context Protocol) client for connecting to external tool servers.
/// Discovers tools via tools/list, executes them via tools/call.
/// Supports Streamable HTTP transport (JSON-RPC over HTTP POST).
@MainActor
final class MCPClient: ObservableObject {
    @Published var servers: [MCPServerConfig] = Config.mcpServers
    @Published var discoveredTools: [MCPTool] = []
    @Published var isDiscovering = false

    // MARK: - Tool Discovery

    /// Discover all tools from all configured MCP servers.
    func discoverAllTools() async {
        isDiscovering = true
        defer { isDiscovering = false }

        var tools: [MCPTool] = []
        for server in servers where server.enabled {
            let serverTools = await discoverTools(from: server)
            tools.append(contentsOf: serverTools)
        }
        discoveredTools = tools
        print("🔌 MCP: discovered \(tools.count) tools from \(servers.filter(\.enabled).count) servers")
    }

    /// Discover tools from a single MCP server.
    func discoverTools(from server: MCPServerConfig) async -> [MCPTool] {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": [:] as [String: Any],
        ]

        guard let data = try? await mcpRequest(server: server, payload: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            print("⚠️ MCP: failed to discover tools from \(server.label)")
            return []
        }

        return toolsArray.compactMap { toolDict -> MCPTool? in
            guard let name = toolDict["name"] as? String else { return nil }
            let description = toolDict["description"] as? String ?? ""
            let inputSchema = toolDict["inputSchema"] as? [String: Any] ?? [:]
            return MCPTool(
                name: name,
                description: description,
                inputSchema: inputSchema,
                serverId: server.id,
                serverLabel: server.label
            )
        }
    }

    // MARK: - Tool Execution

    /// Execute a tool on its MCP server.
    func executeTool(name: String, arguments: [String: Any]) async -> String {
        // Find which server owns this tool
        guard let tool = discoveredTools.first(where: { $0.name == name }),
              let server = servers.first(where: { $0.id == tool.serverId }) else {
            return "MCP tool '\(name)' not found on any server."
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments,
            ] as [String: Any],
        ]

        guard let data = try? await mcpRequest(server: server, payload: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            return "MCP server '\(server.label)' returned an error for tool '\(name)'."
        }

        // MCP tools return content array with text/image parts
        if let content = result["content"] as? [[String: Any]] {
            let texts = content.compactMap { $0["text"] as? String }
            return texts.joined(separator: "\n")
        }

        // Fallback: serialize the result
        if let resultData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted) {
            return String(data: resultData, encoding: .utf8) ?? "Got result from MCP tool."
        }
        return "Tool executed successfully."
    }

    // MARK: - Server Management

    func addServer(_ server: MCPServerConfig) {
        servers.append(server)
        Config.setMCPServers(servers)
    }

    func removeServer(id: String) {
        servers.removeAll { $0.id == id }
        discoveredTools.removeAll { $0.serverId == id }
        Config.setMCPServers(servers)
    }

    func updateServer(_ server: MCPServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
            Config.setMCPServers(servers)
        }
    }

    // MARK: - HTTP Transport

    private func mcpRequest(server: MCPServerConfig, payload: [String: Any]) async throws -> Data {
        guard let url = URL(string: server.url) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth headers
        for (key, value) in server.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("⚠️ MCP error \(httpResponse.statusCode) from \(server.label): \(body.prefix(200))")
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Models

struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: String
    var label: String            // "Home Assistant", "Notion", "GitHub"
    var url: String              // "http://192.168.1.100:8000/mcp"
    var headers: [String: String] // {"Authorization": "Bearer xxx"}
    var enabled: Bool

    static func == (lhs: MCPServerConfig, rhs: MCPServerConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct MCPTool: Identifiable {
    let id = UUID()
    let name: String             // "create_note"
    let description: String      // "Create a note in Notion"
    let inputSchema: [String: Any]
    let serverId: String         // Which server owns this
    let serverLabel: String      // "Notion"

    /// Fully qualified name for display: "notion__create_note"
    var qualifiedName: String { "\(serverLabel.lowercased())__\(name)" }
}
