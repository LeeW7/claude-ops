import Foundation

/// Service for detecting project type based on file presence
public struct ProjectDetectionService: Sendable {
    public init() {}

    /// Detect the project type at a given path
    public func detectProjectType(at path: String) -> ProjectType {
        let fileManager = FileManager.default

        // Check for Flutter project
        let pubspecPath = "\(path)/pubspec.yaml"
        if fileManager.fileExists(atPath: pubspecPath) {
            return .flutter
        }

        // Check for package.json based projects (React Native, web)
        let packageJsonPath = "\(path)/package.json"
        if fileManager.fileExists(atPath: packageJsonPath) {
            // Check if it's a React Native project
            if isReactNativeProject(packageJsonPath: packageJsonPath) {
                return .reactNative
            }
            // Otherwise treat as web project
            return .web
        }

        // Check for iOS project
        let xcodeProjectPaths = [
            "\(path)/ios/Runner.xcworkspace",
            "\(path)/ios/Runner.xcodeproj"
        ]
        for xcodePath in xcodeProjectPaths {
            if fileManager.fileExists(atPath: xcodePath) {
                return .ios
            }
        }

        // Check for standalone iOS project
        let xcworkspaceFiles = try? fileManager.contentsOfDirectory(atPath: path)
            .filter { $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".xcodeproj") }
        if let files = xcworkspaceFiles, !files.isEmpty {
            return .ios
        }

        // Check for Android project
        let androidPaths = [
            "\(path)/android/build.gradle",
            "\(path)/android/build.gradle.kts",
            "\(path)/app/build.gradle",
            "\(path)/app/build.gradle.kts"
        ]
        for androidPath in androidPaths {
            if fileManager.fileExists(atPath: androidPath) {
                return .android
            }
        }

        return .unknown
    }

    /// Check if a package.json indicates a React Native project
    private func isReactNativeProject(packageJsonPath: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: packageJsonPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        // Check dependencies and devDependencies for react-native
        let dependencies = json["dependencies"] as? [String: Any] ?? [:]
        let devDependencies = json["devDependencies"] as? [String: Any] ?? [:]

        return dependencies["react-native"] != nil || devDependencies["react-native"] != nil
    }

    /// Get preview capabilities for a project type
    public func getPreviewCapabilities(for projectType: ProjectType) -> PreviewCapabilities {
        switch projectType {
        case .flutter:
            return PreviewCapabilities(
                canDeploy: true,
                previewType: "web",
                deployCommand: "flutter build web",
                notes: "Flutter web preview"
            )
        case .reactNative:
            return PreviewCapabilities(
                canDeploy: true,
                previewType: "expo",
                deployCommand: "npx expo export --platform web",
                notes: "React Native web preview via Expo"
            )
        case .web:
            return PreviewCapabilities(
                canDeploy: true,
                previewType: "static",
                deployCommand: nil,
                notes: "Static web preview"
            )
        case .ios:
            return PreviewCapabilities(
                canDeploy: false,
                previewType: "simulator",
                deployCommand: nil,
                notes: "iOS requires local simulator"
            )
        case .android:
            return PreviewCapabilities(
                canDeploy: false,
                previewType: "emulator",
                deployCommand: nil,
                notes: "Android requires local emulator"
            )
        case .unknown:
            return PreviewCapabilities(
                canDeploy: false,
                previewType: "unknown",
                deployCommand: nil,
                notes: "Unknown project type"
            )
        }
    }
}

/// Capabilities for preview deployment
public struct PreviewCapabilities: Codable, Sendable {
    /// Whether the project can be deployed for preview
    public let canDeploy: Bool

    /// Type of preview (web, simulator, emulator)
    public let previewType: String

    /// Command to build for deployment (if applicable)
    public let deployCommand: String?

    /// Additional notes about the preview
    public let notes: String

    enum CodingKeys: String, CodingKey {
        case canDeploy = "can_deploy"
        case previewType = "preview_type"
        case deployCommand = "deploy_command"
        case notes
    }
}
