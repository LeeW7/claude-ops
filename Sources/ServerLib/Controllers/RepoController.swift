import Vapor

/// Controller for repository-related endpoints
struct RepoController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("repos", use: listRepos)
    }

    /// List available repositories from repo_map.json
    @Sendable
    func listRepos(req: Request) async throws -> [Repository] {
        guard let repoMap = req.application.repoMap else {
            return []
        }

        return repoMap.allRepositories()
    }
}
