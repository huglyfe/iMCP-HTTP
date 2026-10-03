import Foundation

func invalidArguments(_ message: String) -> ToolFailure {
  ToolFailure("invalid_arguments", message)
}

func validateIdentifier(_ id: String) throws {
  guard !id.isEmpty, id.utf8.count <= 1024 else {
    throw invalidArguments("An exact, nonempty identifier of at most 1024 UTF-8 bytes is required.")
  }
}

// Codable normally ignores unknown fields and treats null as absent. Tool inputs
// deliberately reject both: misspellings must not turn a requested edit into a no-op.
private struct InputKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

extension Decoder {
  func rejectUnknownFields<Key: CodingKey>(_ type: Key.Type) throws {
    let values = try container(keyedBy: InputKey.self)
    guard values.allKeys.allSatisfy({ Key(stringValue: $0.stringValue) != nil }) else {
      throw invalidArguments("Unknown field. Consult the tool schema.")
    }
  }
}

extension KeyedDecodingContainer {
  func optional<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    guard contains(key) else { return nil }
    return try decode(type, forKey: key)
  }
}

func validateTitle(_ title: String) throws {
  guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf8.count <= 1024
  else {
    throw invalidArguments("Title must be nonempty and at most 1024 UTF-8 bytes.")
  }
}
func validatePage(offset: Int, limit: Int, search: String? = nil) throws {
  guard (0...100000).contains(offset), (1...200).contains(limit) else {
    throw invalidArguments("Offset must be 0–100000 and limit 1–200.")
  }
  if let search {
    guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, search.utf8.count <= 512
    else {
      throw invalidArguments("Search must be nonempty and at most 512 UTF-8 bytes.")
    }
  }
}
func validateURL(_ value: String?) throws {
  guard let value else { return }
  guard value.utf8.count <= 4096, let url = URL(string: value), url.scheme != nil else {
    throw invalidArguments("Provide an absolute URL of at most 4096 UTF-8 bytes.")
  }
}
