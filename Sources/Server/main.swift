import ServerLib

@main
struct Server {
    static func main() async throws {
        try await runServer()
    }
}
