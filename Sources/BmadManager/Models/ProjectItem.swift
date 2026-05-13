import Foundation

struct ProjectItem: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL
    let createdAt: Date?

    init(url: URL, createdAt: Date? = nil) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.createdAt = createdAt
    }
}
