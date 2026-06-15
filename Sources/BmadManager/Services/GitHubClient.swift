import Foundation

/// One entry in a created git tree (always a regular-file blob).
struct GitHubTreeEntry: Equatable {
    let path: String
    let blobSHA: String
}

/// The opened pull request.
struct GitHubPullResult: Equatable {
    let htmlURL: String
    let number: Int
}

/// Read-side report for the Settings "Test access" button.
struct GitHubRepoAccess: Equatable {
    let login: String
    let repoFullName: String
    /// Whether the token's effective access includes push (best-effort —
    /// GitHub only returns this when the caller has at least read on the repo).
    let canPush: Bool
}

enum GitHubError: LocalizedError, Equatable {
    case network(String)
    case api(status: Int, message: String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Network error talking to GitHub: \(m)"
        case .api(let status, let message): return "GitHub API error \(status): \(message)"
        case .decode(let m): return "Unexpected GitHub response: \(m)"
        }
    }
}

/// The operations the contribution orchestrator needs. A protocol so the
/// choreography is testable with a fake — no real network in tests.
protocol GitHubClient {
    func whoami() async throws -> String
    func repoAccess(owner: String, repo: String) async throws -> GitHubRepoAccess
    func defaultBranch(owner: String, repo: String) async throws -> String
    func branchHeadSHA(owner: String, repo: String, branch: String) async throws -> String
    func commitTreeSHA(owner: String, repo: String, commitSHA: String) async throws -> String
    /// True if `path` already exists on `branch` (used to block additions that
    /// would overwrite existing repo content).
    func pathExists(owner: String, repo: String, path: String, branch: String) async throws -> Bool
    func createBlob(owner: String, repo: String, contentBase64: String) async throws -> String
    func createTree(
        owner: String, repo: String, baseTree: String, entries: [GitHubTreeEntry]
    ) async throws -> String
    func createCommit(
        owner: String, repo: String, message: String, tree: String, parent: String
    ) async throws -> String
    func createBranchRef(owner: String, repo: String, branch: String, sha: String) async throws
    func createPull(
        owner: String, repo: String, title: String, head: String, base: String, body: String
    ) async throws -> GitHubPullResult
}

/// `URLSession`-backed implementation against api.github.com. Auth uses a
/// `Bearer` token (the REST convention) — distinct from the Basic-auth header
/// `SkillsSyncService` builds for git-over-HTTPS.
struct URLSessionGitHubClient: GitHubClient {
    private static let apiBase = "https://api.github.com"
    private let token: String
    private let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Request plumbing

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: Self.apiBase + path)!)
        req.httpMethod = method
        req.setValue("bmad-manager", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    /// Sends a request, returning the parsed JSON object on 2xx and mapping
    /// non-2xx to `GitHubError.api` with GitHub's own `message`.
    private func sendJSON(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw GitHubError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.decode("no HTTP response")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (200..<300).contains(http.statusCode) {
            return json
        }
        let message = json["message"] as? String ?? "unknown error"
        throw GitHubError.api(status: http.statusCode, message: message)
    }

    private func string(_ json: [String: Any], _ field: String) throws -> String {
        guard let value = json[field] as? String else {
            throw GitHubError.decode("missing `\(field)` in response")
        }
        return value
    }

    // MARK: - Operations

    func whoami() async throws -> String {
        try string(try await sendJSON(request("GET", "/user")), "login")
    }

    func repoAccess(owner: String, repo: String) async throws -> GitHubRepoAccess {
        let login = try await whoami()
        let json = try await sendJSON(request("GET", "/repos/\(owner)/\(repo)"))
        let fullName = try string(json, "full_name")
        let canPush = (json["permissions"] as? [String: Any])?["push"] as? Bool ?? false
        return GitHubRepoAccess(login: login, repoFullName: fullName, canPush: canPush)
    }

    func defaultBranch(owner: String, repo: String) async throws -> String {
        let json = try await sendJSON(request("GET", "/repos/\(owner)/\(repo)"))
        return try string(json, "default_branch")
    }

    func branchHeadSHA(owner: String, repo: String, branch: String) async throws -> String {
        let json = try await sendJSON(request("GET", "/repos/\(owner)/\(repo)/git/ref/heads/\(branch)"))
        guard let object = json["object"] as? [String: Any], let sha = object["sha"] as? String else {
            throw GitHubError.decode("missing object.sha in ref response")
        }
        return sha
    }

    func commitTreeSHA(owner: String, repo: String, commitSHA: String) async throws -> String {
        let json = try await sendJSON(request("GET", "/repos/\(owner)/\(repo)/git/commits/\(commitSHA)"))
        guard let tree = json["tree"] as? [String: Any], let sha = tree["sha"] as? String else {
            throw GitHubError.decode("missing tree.sha in commit response")
        }
        return sha
    }

    func pathExists(owner: String, repo: String, path: String, branch: String) async throws -> Bool {
        var req = request("GET", "/repos/\(owner)/\(repo)/contents/\(path)?ref=\(branch)")
        req.httpMethod = "GET"
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw GitHubError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.decode("no HTTP response")
        }
        switch http.statusCode {
        case 200: return true
        case 404: return false
        default:
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw GitHubError.api(status: http.statusCode, message: json["message"] as? String ?? "unknown error")
        }
    }

    func createBlob(owner: String, repo: String, contentBase64: String) async throws -> String {
        let json = try await sendJSON(request(
            "POST", "/repos/\(owner)/\(repo)/git/blobs",
            body: ["content": contentBase64, "encoding": "base64"]))
        return try string(json, "sha")
    }

    func createTree(
        owner: String, repo: String, baseTree: String, entries: [GitHubTreeEntry]
    ) async throws -> String {
        let tree = entries.map { entry -> [String: Any] in
            ["path": entry.path, "mode": "100644", "type": "blob", "sha": entry.blobSHA]
        }
        let json = try await sendJSON(request(
            "POST", "/repos/\(owner)/\(repo)/git/trees",
            body: ["base_tree": baseTree, "tree": tree]))
        return try string(json, "sha")
    }

    func createCommit(
        owner: String, repo: String, message: String, tree: String, parent: String
    ) async throws -> String {
        let json = try await sendJSON(request(
            "POST", "/repos/\(owner)/\(repo)/git/commits",
            body: ["message": message, "tree": tree, "parents": [parent]]))
        return try string(json, "sha")
    }

    func createBranchRef(owner: String, repo: String, branch: String, sha: String) async throws {
        _ = try await sendJSON(request(
            "POST", "/repos/\(owner)/\(repo)/git/refs",
            body: ["ref": "refs/heads/\(branch)", "sha": sha]))
    }

    func createPull(
        owner: String, repo: String, title: String, head: String, base: String, body: String
    ) async throws -> GitHubPullResult {
        let json = try await sendJSON(request(
            "POST", "/repos/\(owner)/\(repo)/pulls",
            body: ["title": title, "head": head, "base": base, "body": body]))
        guard let url = json["html_url"] as? String, let number = json["number"] as? Int else {
            throw GitHubError.decode("missing html_url/number in pull response")
        }
        return GitHubPullResult(htmlURL: url, number: number)
    }
}
