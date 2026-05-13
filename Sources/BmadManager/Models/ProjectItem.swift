import Foundation

struct ProjectItem: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL

    init(url: URL) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
    }
}
