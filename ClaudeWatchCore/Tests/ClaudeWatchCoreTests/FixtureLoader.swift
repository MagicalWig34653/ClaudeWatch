import Foundation

enum Fixture {
    static func data(_ path: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(path)", withExtension: "json") else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(path)"])
        }
        return try Data(contentsOf: url)
    }
}
