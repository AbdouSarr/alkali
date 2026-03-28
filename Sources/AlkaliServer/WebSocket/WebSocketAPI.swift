//
//  WebSocketAPI.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-22.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

// MARK: - WebSocket Messages

struct WSMessage: Codable, Sendable {
    let type: String
    let params: WSParams?
}

struct WSParams: Codable, Sendable {
    let kinds: [String]?
    let viewID: String?
    let fromTimestamp: UInt64?
    let toTimestamp: UInt64?
    let limit: Int?
}

struct WSResponse: Codable, Sendable {
    let type: String
    let events: [AlkaliEvent]?
    let message: String?
}

// MARK: - WebSocket API Server

public final class WebSocketAPI: @unchecked Sendable {
    private let eventLog: EventLog
    private let port: Int
    private var group: EventLoopGroup?
    private var channel: Channel?
    private var isRunningFlag = false
    private let lock = NSLock()

    public init(eventLog: EventLog, port: Int = 9090) {
        self.eventLog = eventLog
        self.port = port
    }

    public func start() async throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = elg
        let eventLog = self.eventLog

        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { (channel: Channel, _: HTTPRequestHead) in
                channel.pipeline.addHandler(WebSocketHandler(eventLog: eventLog))
            }
        )

        let bootstrap = ServerBootstrap(group: elg)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let httpHandler = HTTPUpgradeRequiredHandler()
                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { _ in
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: config
                ).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }

        let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
        self.channel = serverChannel
        setRunning(true)
        print("Alkali WebSocket server listening on ws://127.0.0.1:\(port)")
    }

    public func stop() {
        setRunning(false)
        channel?.close(mode: .all, promise: nil)
        try? group?.syncShutdownGracefully()
        channel = nil
        group = nil
    }

    private nonisolated func setRunning(_ value: Bool) {
        lock.lock()
        isRunningFlag = value
        lock.unlock()
    }

    public var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunningFlag
    }
}

// MARK: - HTTP Upgrade Handler

private final class HTTPUpgradeRequiredHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard case .head = part else { return }
        let head = HTTPResponseHead(version: .http1_1, status: .upgradeRequired, headers: ["Connection": "close"])
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var body = context.channel.allocator.buffer(capacity: 32)
        body.writeString("WebSocket upgrade required\n")
        context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

// MARK: - WebSocket Frame Handler

private final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let eventLog: EventLog
    private var subscriptionID: UUID?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(eventLog: EventLog) {
        self.eventLog = eventLog
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text:
            handleText(frame, context: context)
        case .connectionClose:
            cleanup()
            context.close(promise: nil)
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        default:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        cleanup()
        context.fireChannelInactive()
    }

    private func handleText(_ frame: WebSocketFrame, context: ChannelHandlerContext) {
        var data = frame.data
        guard let bytes = data.readBytes(length: data.readableBytes),
              let msg = try? decoder.decode(WSMessage.self, from: Data(bytes)) else {
            sendJSON(WSResponse(type: "error", events: nil, message: "Invalid JSON"), context: context)
            return
        }

        switch msg.type {
        case "subscribe":
            cleanup()
            let ctx = context
            let enc = encoder
            subscriptionID = eventLog.subscribe { event in
                let resp = WSResponse(type: "event", events: [event], message: nil)
                guard let json = try? enc.encode(resp) else { return }
                ctx.eventLoop.execute {
                    guard ctx.channel.isActive else { return }
                    var buf = ctx.channel.allocator.buffer(capacity: json.count)
                    buf.writeBytes(json)
                    ctx.writeAndFlush(NIOAny(WebSocketFrame(fin: true, opcode: .text, data: buf)), promise: nil)
                }
            }
            sendJSON(WSResponse(type: "subscribed", events: nil, message: nil), context: context)

        case "unsubscribe":
            cleanup()
            sendJSON(WSResponse(type: "unsubscribed", events: nil, message: nil), context: context)

        case "query":
            let kinds: Set<EventKind>? = msg.params?.kinds.flatMap { strs in
                let mapped = strs.compactMap { EventKind(rawValue: $0) }
                return mapped.isEmpty ? nil : Set(mapped)
            }
            let events = eventLog.query(
                kinds: kinds,
                fromTimestamp: msg.params?.fromTimestamp,
                toTimestamp: msg.params?.toTimestamp,
                limit: msg.params?.limit
            )
            sendJSON(WSResponse(type: "queryResult", events: events, message: nil), context: context)

        default:
            sendJSON(WSResponse(type: "error", events: nil, message: "Unknown: \(msg.type)"), context: context)
        }
    }

    private func cleanup() {
        if let sid = subscriptionID {
            eventLog.unsubscribe(sid)
            subscriptionID = nil
        }
    }

    private func sendJSON(_ response: WSResponse, context: ChannelHandlerContext) {
        guard let json = try? encoder.encode(response) else { return }
        var buf = context.channel.allocator.buffer(capacity: json.count)
        buf.writeBytes(json)
        context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, data: buf)), promise: nil)
    }
}
