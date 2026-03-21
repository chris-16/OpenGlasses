import Foundation

/// Routes tool calls: native tools → MCP servers → OpenClaw fallback.
@MainActor
final class NativeToolRouter {
    let registry: NativeToolRegistry
    var openClawBridge: OpenClawBridge?
    var mcpClient: MCPClient?

    init(registry: NativeToolRegistry, openClawBridge: OpenClawBridge? = nil) {
        self.registry = registry
        self.openClawBridge = openClawBridge
    }

    /// Handle a tool call by name. Routing order: native → MCP → OpenClaw → error.
    func handleToolCall(name: String, args: [String: Any]) async -> ToolResult {
        // 1. Check native tools first
        if let tool = registry.tool(named: name) {
            NSLog("[NativeToolRouter] Executing native tool: %@", name)
            do {
                let result = try await tool.execute(args: args)
                NSLog("[NativeToolRouter] Native tool %@ succeeded: %@", name, String(result.prefix(200)))
                return .success(result)
            } catch {
                NSLog("[NativeToolRouter] Native tool %@ failed: %@", name, error.localizedDescription)
                return .failure("Tool error: \(error.localizedDescription)")
            }
        }

        // 2. Check MCP servers for the tool
        if let mcp = mcpClient, mcp.discoveredTools.contains(where: { $0.name == name }) {
            NSLog("[NativeToolRouter] Executing MCP tool: %@", name)
            let result = await mcp.executeTool(name: name, arguments: args)
            return .success(result)
        }

        // 3. Fall through to OpenClaw for "execute" or unknown tools
        if let bridge = openClawBridge, Config.isOpenClawConfigured {
            let taskDesc = args["task"] as? String ?? String(describing: args)
            NSLog("[NativeToolRouter] Delegating to OpenClaw: %@(%@)", name, String(taskDesc.prefix(100)))
            return await bridge.delegateTask(task: taskDesc, toolName: name)
        }

        return .failure("Unknown tool: \(name)")
    }
}
