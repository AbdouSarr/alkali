//
//  Trampoline.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-08.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if arch(arm64)
import Foundation
import Darwin.Mach
import AlkaliCore

/// ARM64 function trampoline — patches a function entry point to redirect to new code.
///
/// Mechanism:
/// 1. Allocate executable memory for new code
/// 2. Copy new function body to allocated region
/// 3. Save the original instruction at the function entry
/// 4. Write an unconditional branch (B) to the new code
/// 5. Flush instruction cache
private func getPageSize() -> Int {
    Int(sysconf(_SC_PAGESIZE))
}

private func getCurrentTask() -> mach_port_t {
    mach_task_self_
}

public struct Trampoline: Sendable {

    /// Apply a patch: redirect `originalAddress` to execute `newCode` instead.
    public static func patch(
        originalAddress: UnsafeMutableRawPointer,
        newCode: Data
    ) throws -> PatchRecord {
        // 1. Allocate executable memory
        var newCodeAddress: mach_vm_address_t = 0
        let pageSize = mach_vm_size_t(getPageSize())
        let allocSize = max(pageSize, mach_vm_size_t(newCode.count))

        let kr = mach_vm_allocate(getCurrentTask(), &newCodeAddress, allocSize, VM_FLAGS_ANYWHERE)
        guard kr == KERN_SUCCESS else {
            throw PatchError.allocationFailed(kr)
        }

        // 2. Copy new code
        _ = newCode.withUnsafeBytes { buffer in
            memcpy(UnsafeMutableRawPointer(bitPattern: UInt(newCodeAddress))!, buffer.baseAddress!, newCode.count)
        }

        // 3. Make the new code executable
        let protectKr = mach_vm_protect(getCurrentTask(), newCodeAddress, allocSize, 0, VM_PROT_READ | VM_PROT_EXECUTE)
        guard protectKr == KERN_SUCCESS else {
            throw PatchError.protectFailed(protectKr)
        }

        // 4. Save original instruction
        let originalInstruction = originalAddress.load(as: UInt32.self)

        // 5. Make original page writable
        let originalPage = mach_vm_address_t(UInt(bitPattern: originalAddress)) & ~mach_vm_address_t(pageSize - 1)
        let pageProtectKr = mach_vm_protect(getCurrentTask(), originalPage, pageSize, 0,
                                             VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)
        guard pageProtectKr == KERN_SUCCESS else {
            throw PatchError.protectFailed(pageProtectKr)
        }

        // 6. Calculate branch offset and write B instruction
        let offset = Int64(newCodeAddress) - Int64(UInt(bitPattern: originalAddress))
        let branchImm = offset >> 2
        guard branchImm >= -0x2000000 && branchImm <= 0x1FFFFFF else {
            throw PatchError.branchOutOfRange
        }

        let branchInstruction: UInt32 = 0x14000000 | UInt32(branchImm & 0x03FFFFFF)
        originalAddress.storeBytes(of: branchInstruction, as: UInt32.self)

        // 7. Flush instruction cache
        sys_icache_invalidate(originalAddress, 4)
        sys_icache_invalidate(UnsafeMutableRawPointer(bitPattern: UInt(newCodeAddress))!, newCode.count)

        // 8. Restore original page to RX
        mach_vm_protect(getCurrentTask(), originalPage, pageSize, 0, VM_PROT_READ | VM_PROT_EXECUTE)

        return PatchRecord(
            originalAddress: UInt64(UInt(bitPattern: originalAddress)),
            newCodeAddress: UInt64(newCodeAddress),
            newCodeSize: UInt64(allocSize),
            originalInstruction: originalInstruction
        )
    }

    /// Revert a patch by restoring the original instruction.
    public static func revert(_ record: PatchRecord) throws {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: UInt(record.originalAddress)) else {
            throw PatchError.invalidAddress
        }

        let pageSize = mach_vm_size_t(getPageSize())
        let page = mach_vm_address_t(record.originalAddress) & ~mach_vm_address_t(pageSize - 1)

        // Make writable
        mach_vm_protect(getCurrentTask(), page, pageSize, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)

        // Restore original instruction
        ptr.storeBytes(of: record.originalInstruction, as: UInt32.self)
        sys_icache_invalidate(ptr, 4)

        // Restore RX
        mach_vm_protect(getCurrentTask(), page, pageSize, 0, VM_PROT_READ | VM_PROT_EXECUTE)

        // Free allocated code
        mach_vm_deallocate(getCurrentTask(), mach_vm_address_t(record.newCodeAddress), mach_vm_size_t(record.newCodeSize))
    }
}

public struct PatchRecord: Sendable {
    public let originalAddress: UInt64
    public let newCodeAddress: UInt64
    public let newCodeSize: UInt64
    public let originalInstruction: UInt32

    public init(originalAddress: UInt64, newCodeAddress: UInt64, newCodeSize: UInt64, originalInstruction: UInt32) {
        self.originalAddress = originalAddress
        self.newCodeAddress = newCodeAddress
        self.newCodeSize = newCodeSize
        self.originalInstruction = originalInstruction
    }
}

public enum PatchError: Error, LocalizedError {
    case allocationFailed(kern_return_t)
    case protectFailed(kern_return_t)
    case branchOutOfRange
    case invalidAddress

    public var errorDescription: String? {
        switch self {
        case .allocationFailed(let kr): return "mach_vm_allocate failed: \(kr)"
        case .protectFailed(let kr): return "mach_vm_protect failed: \(kr)"
        case .branchOutOfRange: return "Branch target out of range for B instruction"
        case .invalidAddress: return "Invalid address"
        }
    }
}

#endif
