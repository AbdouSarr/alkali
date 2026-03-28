//
//  AlkaliClient.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-26.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Swift client for connecting to an Alkali daemon and calling MCP tools programmatically.
public final class AlkaliClient: @unchecked Sendable {
    private let process: Process
    private let stdin: Pipe
    private let stdout: Pipe
    private var nextID: Int = 1
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    /// Connect to an Alkali MCP server by launching it as a subprocess.
    public init(alkaliPath: String = "alkali", projectRoot: String) throws {
        self.process = Process()
        self.stdin = Pipe()
        self.stdout = Pipe()

        process.executableURL = URL(fileURLWithPath: alkaliPath)
        process.arguments = ["mcp-server", "--project-root", projectRoot]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Send initialize
        _ = try sendRequest(method: "initialize", params: [:])
        _ = try sendNotification(method: "notifications/initialized", params: [:])
    }

    deinit {
        process.terminate()
    }

    /// Call an MCP tool and return the text result.
    public func callTool(name: String, arguments: [String: Any] = [:]) throws -> String {
        let params: [String: Any] = ["name": name, "arguments": arguments]
        let response = try sendRequest(method: "tools/call", params: params)
        guard let result = response["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ClientError.invalidResponse
        }
        return text
    }

    /// Call a tool and decode the JSON result into a Codable type.
    public func callTool<T: Decodable>(name: String, arguments: [String: Any] = [:], as type: T.Type) throws -> T {
        let text = try callTool(name: name, arguments: arguments)
        guard let data = text.data(using: .utf8) else { throw ClientError.invalidResponse }
        return try decoder.decode(type, from: data)
    }

    /// List available tools.
    public func listTools() throws -> [[String: Any]] {
        let response = try sendRequest(method: "tools/list", params: [:])
        guard let result = response["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]] else {
            return []
        }
        return tools
    }

    /// Disconnect from the daemon.
    public func disconnect() {
        process.terminate()
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any]) throws -> [String: Any] {
        lock.lock()
        let id = nextID
        nextID += 1
        lock.unlock()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        guard var line = String(data: data, encoding: .utf8) else {
            throw ClientError.serializationFailed
        }
        line += "\n"
        stdin.fileHandleForWriting.write(line.data(using: .utf8)!)

        // Read response line
        let responseData = stdout.fileHandleForReading.availableData
        guard let responseStr = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let responseJSON = responseStr.data(using: .utf8),
              let response = try JSONSerialization.jsonObject(with: responseJSON) as? [String: Any] else {
            throw ClientError.invalidResponse
        }

        return response
    }

    private func sendNotification(method: String, params: [String: Any]) throws -> [String: Any]? {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        guard var line = String(data: data, encoding: .utf8) else { return nil }
        line += "\n"
        stdin.fileHandleForWriting.write(line.data(using: .utf8)!)
        return nil
    }
}

public enum ClientError: Error {
    case invalidResponse
    case serializationFailed
    case connectionFailed
}
