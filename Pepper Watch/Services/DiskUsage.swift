//
//  DiskUsage.swift
//  Pepper Watch
//

import Foundation

nonisolated enum DiskUsage {
    /// Total allocated size of every file under `url`.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: keys)
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    @concurrent static func sizeInBackground(of url: URL) async -> Int64 {
        size(of: url)
    }
}
