import Foundation
import SwiftMCP

@Schema
struct ContactValue: Codable, Sendable {
  /// Exact native label token or custom text. Preserve returned labels when editing.
  var label: String?
  let value: String
}
@Schema
struct ContactAddress: Codable, Sendable {
  /// Exact native label token or custom text. Preserve returned labels when editing.
  var label: String?
  var street: String?
  var city: String?
  var state: String?
  var postalCode: String?
  var country: String?
  /// Two-letter country code.
  var countryCode: String?
}
@Schema
struct ContactBirthday: Codable, Sendable {
  let month: Int
  let day: Int
  var year: Int?
}
enum ContactClearField: String, Codable, CaseIterable, Sendable { case birthday }

@Schema
struct ContactChanges: Codable, Sendable {
  /// Empty strings clear text fields. Omitted fields are preserved.
  var givenName: String?
  var middleName: String?
  var familyName: String?
  var prefix: String?
  var suffix: String?
  var nickname: String?
  var organization: String?
  var department: String?
  var jobTitle: String?
  /// Replace the field's values; [] clears it.
  var phones: [ContactValue]?
  var emails: [ContactValue]?
  var urls: [ContactValue]?
  var addresses: [ContactAddress]?
  var birthday: ContactBirthday?
  var clear: [ContactClearField]?

  func validate(creating: Bool = false) throws {
    let strings = [
      givenName, middleName, familyName, prefix, suffix, nickname, organization, department,
      jobTitle,
    ]
    guard strings.allSatisfy({ ($0?.utf8.count ?? 0) <= 1024 }) else {
      throw invalidArguments("Contact text is too long.")
    }
    if creating,
      ![givenName, familyName, organization].contains(where: {
        !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
      })
    {
      throw invalidArguments("Create requires a givenName, familyName, or organization.")
    }
    for values in [phones, emails, urls] {
      guard (values?.count ?? 0) <= 50 else {
        throw invalidArguments("Use at most 50 values per field.")
      }
      for entry in values ?? [] {
        guard !entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          entry.value.utf8.count <= 4096, (entry.label?.utf8.count ?? 0) <= 128
        else {
          throw invalidArguments("Invalid contact value or label.")
        }
      }
    }
    for entry in urls ?? [] { try validateURL(entry.value) }
    guard (addresses?.count ?? 0) <= 20 else { throw invalidArguments("Use at most 20 addresses.") }
    for address in addresses ?? [] {
      guard
        [address.street, address.city, address.state, address.postalCode, address.country]
          .allSatisfy({ ($0?.utf8.count ?? 0) <= 4096 }),
        (address.label?.utf8.count ?? 0) <= 128,
        address.countryCode.map({
          $0.count == 2 && $0.range(of: "^[A-Za-z]{2}$", options: .regularExpression) != nil
        }) ?? true
      else {
        throw invalidArguments("Invalid address.")
      }
    }
    if let birthday {
      guard (1...9999).contains(birthday.year ?? 2000) else {
        throw invalidArguments("Invalid birth year.")
      }
      _ = try AppleDate(
        date: String(format: "%04d-%02d-%02d", birthday.year ?? 2000, birthday.month, birthday.day)
      ).components()
    }
    guard (clear?.count ?? 0) <= 1, !(clear?.contains(.birthday) == true && birthday != nil) else {
      throw invalidArguments("Conflicting clear fields.")
    }
    guard
      strings.contains(where: { $0 != nil }) || phones != nil || emails != nil || urls != nil
        || addresses != nil || birthday != nil || clear?.isEmpty == false
    else {
      throw invalidArguments("Provide at least one change.")
    }
  }
}

@Schema
struct ContactRecord: Codable, Sendable {
  let id: String
  let givenName: String?
  let middleName: String?
  let familyName: String?
  let prefix: String?
  let suffix: String?
  let nickname: String?
  let organization: String?
  let department: String?
  let jobTitle: String?
  let phones: [ContactValue]?
  let emails: [ContactValue]?
  let urls: [ContactValue]?
  let addresses: [ContactAddress]?
  let birthday: ContactBirthday?
}
@Schema
struct ContactSummary: Codable, Sendable {
  let id: String
  let name: String
  let phones: [ContactValue]?
  let emails: [ContactValue]?
}
@Schema
struct ContactPage: Codable, Sendable {
  let contacts: [ContactSummary]
  let nextOffset: Int?
}
@Schema
struct ContactGroup: Codable, Sendable {
  let id: String
  let name: String
}
@Schema
struct ContactGroups: Codable, Sendable { let groups: [ContactGroup] }
@Schema
struct GroupMembership: Codable, Sendable {
  let contactID: String
  let groupID: String
  let member: Bool
}

@MainActor
protocol ContactAccess: Sendable {
  var available: Bool { get }
  func accounts() throws -> AppleAccounts
  func fetch(accountID: String, search: String?, groupID: String?, offset: Int, limit: Int) throws
    -> ContactPage
  func get(id: String) throws -> ContactRecord
  func create(accountID: String, changes: ContactChanges) throws -> ContactRecord
  func edit(id: String, changes: ContactChanges) throws -> ContactRecord
  func delete(id: String) throws
  func groups(accountID: String) throws -> ContactGroups
  func createGroup(accountID: String, name: String) throws -> ContactGroup
  func renameGroup(id: String, name: String) throws -> ContactGroup
  func deleteGroup(id: String) throws
  func membership(contactID: String, groupID: String, member: Bool) throws -> GroupMembership
}

extension ContactValue {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    label = try values.optional(String.self, forKey: .label)
    value = try values.decode(String.self, forKey: .value)
  }
}

extension ContactAddress {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    label = try values.optional(String.self, forKey: .label)
    street = try values.optional(String.self, forKey: .street)
    city = try values.optional(String.self, forKey: .city)
    state = try values.optional(String.self, forKey: .state)
    postalCode = try values.optional(String.self, forKey: .postalCode)
    country = try values.optional(String.self, forKey: .country)
    countryCode = try values.optional(String.self, forKey: .countryCode)
  }
}

extension ContactBirthday {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    month = try values.decode(Int.self, forKey: .month)
    day = try values.decode(Int.self, forKey: .day)
    year = try values.optional(Int.self, forKey: .year)
  }
}

extension ContactChanges {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    givenName = try values.optional(String.self, forKey: .givenName)
    middleName = try values.optional(String.self, forKey: .middleName)
    familyName = try values.optional(String.self, forKey: .familyName)
    prefix = try values.optional(String.self, forKey: .prefix)
    suffix = try values.optional(String.self, forKey: .suffix)
    nickname = try values.optional(String.self, forKey: .nickname)
    organization = try values.optional(String.self, forKey: .organization)
    department = try values.optional(String.self, forKey: .department)
    jobTitle = try values.optional(String.self, forKey: .jobTitle)
    phones = try values.optional([ContactValue].self, forKey: .phones)
    emails = try values.optional([ContactValue].self, forKey: .emails)
    urls = try values.optional([ContactValue].self, forKey: .urls)
    addresses = try values.optional([ContactAddress].self, forKey: .addresses)
    birthday = try values.optional(ContactBirthday.self, forKey: .birthday)
    clear = try values.optional([ContactClearField].self, forKey: .clear)
  }
}
