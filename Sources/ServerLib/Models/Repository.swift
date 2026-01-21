import Vapor
import Foundation

/// Repository information
public struct Repository: Content, Identifiable {
    public var id: String { fullName }
    public let name: String
    public let fullName: String
    public let path: String

    public init(name: String, fullName: String, path: String) {
        self.name = name
        self.fullName = fullName
        self.path = path
    }

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case path
    }
}

/// Repo map loaded from repo_map.json
/// Maps local filesystem paths to GitHub repository URLs
public struct RepoMap {
    /// Dictionary mapping local path -> repo URL
    private var mapping: [String: String]

    public init(mapping: [String: String]) {
        self.mapping = mapping
    }

    /// Load repo map from JSON file
    public static func load(from path: String) throws -> RepoMap {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let mapping = try JSONDecoder().decode([String: String].self, from: data)
        return RepoMap(mapping: mapping)
    }

    /// Save repo map to JSON file
    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(mapping)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Add a repository to the map
    public mutating func addRepository(localPath: String, githubUrl: String) {
        mapping[localPath] = githubUrl
    }

    /// Remove a repository from the map
    public mutating func removeRepository(localPath: String) {
        mapping.removeValue(forKey: localPath)
    }

    /// Get local path for a given repo name (e.g., "owner/repo-name")
    public func getPath(for repoName: String) -> String? {
        for (folderPath, repoUrl) in mapping {
            let mapName: String
            if repoUrl.contains("github.com/") {
                mapName = repoUrl
                    .split(separator: "github.com/").last
                    .map(String.init)?
                    .replacingOccurrences(of: ".git", with: "") ?? repoUrl
            } else {
                mapName = repoUrl
            }

            if mapName.lowercased() == repoName.lowercased() {
                return folderPath
            }
        }
        return nil
    }

    /// Get full repo name for a slug (e.g., "repo-name" -> "owner/repo-name")
    public func getFullName(forSlug slug: String) -> String? {
        for (_, repoUrl) in mapping {
            let fullName: String
            if repoUrl.contains("github.com/") {
                fullName = repoUrl
                    .split(separator: "github.com/").last
                    .map(String.init)?
                    .replacingOccurrences(of: ".git", with: "") ?? repoUrl
            } else {
                fullName = repoUrl
            }
            let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
            if name.lowercased() == slug.lowercased() {
                return fullName
            }
        }
        return nil
    }

    /// Get all repositories as a list
    public func allRepositories() -> [Repository] {
        return mapping.map { (folderPath, repoUrl) in
            let fullName: String
            if repoUrl.contains("github.com/") {
                fullName = repoUrl
                    .split(separator: "github.com/").last
                    .map(String.init)?
                    .replacingOccurrences(of: ".git", with: "") ?? repoUrl
            } else {
                fullName = repoUrl
            }
            let name = fullName.split(separator: "/").last.map(String.init) ?? fullName

            return Repository(name: name, fullName: fullName, path: folderPath)
        }
    }
}
