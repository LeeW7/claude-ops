import Vapor
import Foundation

/// Controller for image upload endpoints
struct ImageController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.on(.POST, "images", "upload", body: .collect(maxSize: "10mb"), use: uploadImage)
    }

    /// Upload an image and return a URL using GitHub Gist
    @Sendable
    func uploadImage(req: Request) async throws -> Response {
        // Get the uploaded file
        guard let file = try? req.content.decode(ImageUpload.self).image else {
            throw Abort(.badRequest, reason: "No image file provided")
        }

        guard let data = file.data.getData(at: 0, length: file.data.readableBytes) else {
            throw Abort(.badRequest, reason: "Could not read image data")
        }

        // Determine file extension
        let filename = file.filename ?? "image.png"
        var ext = filename.split(separator: ".").last.map(String.init)?.lowercased() ?? "png"
        if !["png", "jpg", "jpeg", "gif", "webp"].contains(ext) {
            ext = "png"
        }

        // Create unique filename
        let uniqueName = "feedback-screenshot-\(UUID().uuidString.prefix(8)).\(ext)"

        // Base64 encode the image
        let base64Data = data.base64EncodedString()

        // Create gist content with embedded image
        let gistContent = "# Feedback Screenshot\n\n![\\(uniqueName)](data:image/\(ext);base64,\(base64Data))"

        // Create gist
        let gistUrl = try await req.application.githubService.createGist(
            content: gistContent,
            filename: "\(uniqueName).md",
            description: "Feedback screenshot: \(uniqueName)"
        )

        // Try to get raw URL
        var rawUrl: String? = nil
        if gistUrl.contains("gist.github.com") {
            let gistId = gistUrl.split(separator: "/").last.map(String.init) ?? ""
            rawUrl = try? await req.application.githubService.getGistRawURL(gistID: gistId)
        }

        var response: [String: Any] = [
            "status": "uploaded",
            "url": gistUrl,
            "filename": uniqueName
        ]

        if let rawUrl = rawUrl {
            response["raw_url"] = rawUrl
        }

        let responseData = try JSONSerialization.data(withJSONObject: response)
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(data: responseData)
        )
    }
}

/// Model for multipart image upload
struct ImageUpload: Content {
    var image: File
}
