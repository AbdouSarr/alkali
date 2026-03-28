//
//  FileWatcher.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-12.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore
import CoreServices

/// Watches a directory recursively for file changes using macOS FSEvents.
///
/// Monitors .swift, .xcassets, .json, .plist, and .pbxproj files.
/// Rapid changes are debounced (coalesced within 200ms) before invoking the callback.
public final class FileWatcher: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "alkali.filewatcher")
    private var stream: FSEventStreamRef?
    private var callback: (@Sendable (_ changedPaths: [String]) -> Void)?

    /// Extensions that trigger change notifications.
    private static let relevantExtensions: Set<String> = [
        "swift", "xcassets", "json", "plist", "pbxproj"
    ]

    /// Debounce interval in seconds.
    private static let debounceInterval: TimeInterval = 0.2

    /// Accumulated paths during debounce window.
    private var pendingPaths: Set<String> = []

    /// Work item for the debounce timer; cancelled and re-created on each new event batch.
    private var debounceWorkItem: DispatchWorkItem?

    public init(path: String) {
        self.path = path
    }

    deinit {
        stop()
    }

    /// Start watching the directory. The `onChange` callback fires with accumulated
    /// changed file paths after the debounce window closes.
    public func start(onChange: @escaping @Sendable (_ changedPaths: [String]) -> Void) {
        stop() // ensure clean state
        self.callback = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,  // Latency: 50ms — fine-grained, debouncing is handled separately
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Stop watching and release all resources.
    public func stop() {
        queue.sync { [weak self] in
            self?.debounceWorkItem?.cancel()
            self?.debounceWorkItem = nil
            self?.pendingPaths.removeAll()
        }

        if let stream = self.stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        self.callback = nil
    }

    // MARK: - Internal event handling

    /// Called from the FSEvents C callback on our dispatch queue.
    fileprivate func handleEvents(paths: [String]) {
        // Filter to relevant file extensions
        let relevant = paths.filter { path in
            let ext = (path as NSString).pathExtension.lowercased()
            return FileWatcher.relevantExtensions.contains(ext)
        }

        guard !relevant.isEmpty else { return }

        // Accumulate into the pending set
        for p in relevant {
            pendingPaths.insert(p)
        }

        // Cancel any existing debounce timer and start a new one
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingPaths()
        }
        debounceWorkItem = workItem
        queue.asyncAfter(
            deadline: .now() + FileWatcher.debounceInterval,
            execute: workItem
        )
    }

    /// Flush accumulated paths and invoke the callback.
    private func flushPendingPaths() {
        guard !pendingPaths.isEmpty else { return }
        let paths = Array(pendingPaths).sorted()
        pendingPaths.removeAll()
        callback?(paths)
    }
}

// MARK: - FSEvents C callback

/// Free function used as the FSEventStreamCallback.
/// `info` is an unretained pointer to the FileWatcher instance.
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray of CFString
    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray?.self) else { return }
    let count = CFArrayGetCount(cfPaths)

    var paths = [String]()
    paths.reserveCapacity(count)
    for i in 0..<count {
        if let cfStr = unsafeBitCast(CFArrayGetValueAtIndex(cfPaths, i), to: CFString?.self) {
            paths.append(cfStr as String)
        }
    }

    watcher.handleEvents(paths: paths)
}
