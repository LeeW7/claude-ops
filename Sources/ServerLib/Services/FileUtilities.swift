import Foundation

/// Shared file reading utilities
public enum FileUtilities {

    /// Read the last N bytes of a file efficiently
    /// Returns nil if the file doesn't exist or can't be read
    public static func readFileTail(path: String, maxBytes: UInt64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let startPos = fileSize > maxBytes ? fileSize - maxBytes : 0
        handle.seek(toFileOffset: startPos)

        guard let data = try? handle.readToEnd(),
              var content = String(data: data, encoding: .utf8) else {
            return nil
        }

        // If we started mid-file, skip to the first complete line
        if startPos > 0 {
            if let firstNewline = content.firstIndex(of: "\n") {
                content = String(content[content.index(after: firstNewline)...])
            }
        }

        return content
    }

    /// Read the last N bytes of a file with a truncation notice for large files
    /// Returns a default message if the file doesn't exist
    public static func readFileTailWithNotice(path: String, maxBytes: UInt64, defaultMessage: String = "") -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            return defaultMessage
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            return defaultMessage
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let startPos = fileSize > maxBytes ? fileSize - maxBytes : 0
        handle.seek(toFileOffset: startPos)

        guard let data = try? handle.readToEnd(),
              var content = String(data: data, encoding: .utf8) else {
            return defaultMessage
        }

        // If we started mid-file, skip to the first complete line and add a notice
        if startPos > 0 {
            if let firstNewline = content.firstIndex(of: "\n") {
                content = String(content[content.index(after: firstNewline)...])
            }
            let sizeKB = maxBytes / 1024
            content = "... (showing last ~\(sizeKB)KB of log) ...\n\n" + content
        }

        return content
    }
}
