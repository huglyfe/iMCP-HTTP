import Contacts
import Foundation

@MainActor
public final class NativeContacts: AppleAccess, ContactAccess {
  public private(set) var enabled: Bool
  private lazy var store = CNContactStore()
  public init(enabled: Bool = false) { self.enabled = enabled }
  public var available: Bool {
    enabled && CNContactStore.authorizationStatus(for: .contacts) == .authorized
  }
  public func setEnabled(_ enabled: Bool) { self.enabled = enabled }
  public func requestAccess() async throws -> Bool { try await store.requestAccess(for: .contacts) }

  private static var keys: [CNKeyDescriptor] {
    [
      CNContactIdentifierKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
      CNContactNamePrefixKey, CNContactNameSuffixKey, CNContactNicknameKey,
      CNContactOrganizationNameKey,
      CNContactDepartmentNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey,
      CNContactEmailAddressesKey,
      CNContactUrlAddressesKey, CNContactPostalAddressesKey, CNContactBirthdayKey,
    ].map { $0 as CNKeyDescriptor }
  }
  private static var summaryKeys: [CNKeyDescriptor] {
    [
      CNContactIdentifierKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
      CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
    ].map { $0 as CNKeyDescriptor }
  }
  func accounts() throws -> AppleAccounts {
    try requireAccess()
    do {
      return AppleAccounts(
        accounts: try store.containers(matching: nil).map {
          AppleAccount(id: $0.identifier, title: $0.name)
        }.sorted { $0.id < $1.id })
    } catch { throw ToolFailure("read_failed", "Contacts accounts could not be read.") }
  }
  private func requireAccount(_ id: String) throws {
    try validateIdentifier(id)
    guard try accounts().accounts.contains(where: { $0.id == id }) else {
      throw ToolFailure("not_found", "Contacts account was not found.")
    }
  }
  private func enumerate(
    _ predicate: NSPredicate, keys: [CNKeyDescriptor],
    body: (CNContact, UnsafeMutablePointer<ObjCBool>) -> Void
  ) throws {
    let request = CNContactFetchRequest(keysToFetch: keys)
    request.predicate = predicate
    request.unifyResults = false
    request.sortOrder = .userDefault
    do { try store.enumerateContacts(with: request, usingBlock: body) } catch {
      throw ToolFailure("read_failed", "Contacts could not be read.")
    }
  }
  private func contact(_ id: String) throws -> CNContact {
    try requireAccess()
    var matches: [CNContact] = []
    try enumerate(CNContact.predicateForContacts(withIdentifiers: [id]), keys: Self.keys) {
      value, _ in
      if value.identifier == id { matches.append(value) }
    }
    guard matches.count == 1, let value = matches.first else {
      throw ToolFailure("not_found", "Exact contact was not found. Fetch contacts again.")
    }
    return value
  }
  func fetch(accountID: String, search: String?, groupID: String?, offset: Int, limit: Int) throws
    -> ContactPage
  {
    try requireAccess()
    try requireAccount(accountID)
    let predicate: NSPredicate
    if let groupID {
      guard try groups(accountID: accountID).groups.contains(where: { $0.id == groupID }) else {
        throw ToolFailure("not_found", "Group was not found in this account.")
      }
      predicate = CNContact.predicateForContactsInGroup(withIdentifier: groupID)
    } else {
      predicate = CNContact.predicateForContactsInContainer(withIdentifier: accountID)
    }
    var skipped = 0
    var records: [ContactSummary] = []
    try enumerate(predicate, keys: Self.summaryKeys) { contact, stop in
      let record = Self.summary(contact)
      if let search {
        let texts =
          [record.name] + (record.phones ?? []).map(\.value) + (record.emails ?? []).map(\.value)
        guard
          texts.contains(where: {
            $0.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil
          })
        else { return }
      }
      if skipped < offset {
        skipped += 1
        return
      }
      records.append(record)
      if records.count > limit { stop.pointee = true }
    }
    return ContactPage(
      contacts: Array(records.prefix(limit)),
      nextOffset: records.count > limit ? offset + limit : nil)
  }
  func get(id: String) throws -> ContactRecord { Self.record(try contact(id)) }
  func create(accountID: String, changes: ContactChanges) throws -> ContactRecord {
    try requireAccess()
    try requireAccount(accountID)
    let contact = CNMutableContact()
    Self.apply(changes, to: contact)
    let request = CNSaveRequest()
    request.add(contact, toContainerWithIdentifier: accountID)
    try save(request)
    return Self.record(contact)
  }
  func edit(id: String, changes: ContactChanges) throws -> ContactRecord {
    let contact = try contact(id).mutableCopy() as! CNMutableContact
    Self.apply(changes, to: contact)
    let request = CNSaveRequest()
    request.update(contact)
    try save(request)
    return Self.record(contact)
  }
  func delete(id: String) throws {
    let contact = try contact(id).mutableCopy() as! CNMutableContact
    let request = CNSaveRequest()
    request.delete(contact)
    try save(request)
  }
  func groups(accountID: String) throws -> ContactGroups {
    try requireAccess()
    try requireAccount(accountID)
    do {
      return ContactGroups(
        groups: try store.groups(
          matching: CNGroup.predicateForGroupsInContainer(withIdentifier: accountID)
        )
        .map { ContactGroup(id: $0.identifier, name: $0.name) }.sorted { $0.id < $1.id })
    } catch { throw ToolFailure("read_failed", "Contact groups could not be read.") }
  }
  private func group(_ id: String) throws -> CNMutableGroup {
    try requireAccess()
    let groups: [CNGroup]
    do {
      groups = try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id]))
    } catch { throw ToolFailure("read_failed", "Contact groups could not be read.") }
    guard groups.count == 1, let group = groups.first, group.identifier == id else {
      throw ToolFailure("not_found", "Exact contact group was not found.")
    }
    return group.mutableCopy() as! CNMutableGroup
  }
  func createGroup(accountID: String, name: String) throws -> ContactGroup {
    try requireAccess()
    try requireAccount(accountID)
    try validateTitle(name)
    let group = CNMutableGroup()
    group.name = name
    let request = CNSaveRequest()
    request.add(group, toContainerWithIdentifier: accountID)
    try save(request)
    return ContactGroup(id: group.identifier, name: group.name)
  }
  func renameGroup(id: String, name: String) throws -> ContactGroup {
    try validateTitle(name)
    let group = try group(id)
    group.name = name
    let request = CNSaveRequest()
    request.update(group)
    try save(request)
    return ContactGroup(id: group.identifier, name: group.name)
  }
  func deleteGroup(id: String) throws {
    let group = try group(id)
    let request = CNSaveRequest()
    request.delete(group)
    try save(request)
  }
  func membership(contactID: String, groupID: String, member: Bool) throws -> GroupMembership {
    let contact = try contact(contactID)
    let group = try group(groupID)
    var existing = false
    try enumerate(
      CNContact.predicateForContactsInGroup(withIdentifier: groupID),
      keys: [CNContactIdentifierKey as CNKeyDescriptor]
    ) { value, stop in
      if value.identifier == contactID {
        existing = true
        stop.pointee = true
      }
    }
    if member != existing {
      let request = CNSaveRequest()
      if member {
        request.addMember(contact, to: group)
      } else {
        request.removeMember(contact, from: group)
      }
      try save(request)
    }
    return GroupMembership(contactID: contactID, groupID: groupID, member: member)
  }
  private func save(_ request: CNSaveRequest) throws {
    request.shouldRefetchContacts = true
    do { try store.execute(request) } catch {
      throw ToolFailure(
        "write_failed", "Contacts did not confirm the write. Read the target before retrying.")
    }
  }

  static func apply(_ changes: ContactChanges, to contact: CNMutableContact) {
    if let value = changes.givenName { contact.givenName = value }
    if let value = changes.middleName { contact.middleName = value }
    if let value = changes.familyName { contact.familyName = value }
    if let value = changes.prefix { contact.namePrefix = value }
    if let value = changes.suffix { contact.nameSuffix = value }
    if let value = changes.nickname { contact.nickname = value }
    if let value = changes.organization { contact.organizationName = value }
    if let value = changes.department { contact.departmentName = value }
    if let value = changes.jobTitle { contact.jobTitle = value }
    if let values = changes.phones {
      contact.phoneNumbers = values.map {
        CNLabeledValue(label: $0.label, value: CNPhoneNumber(stringValue: $0.value))
      }
    }
    if let values = changes.emails {
      contact.emailAddresses = values.map {
        CNLabeledValue(label: $0.label, value: $0.value as NSString)
      }
    }
    if let values = changes.urls {
      contact.urlAddresses = values.map {
        CNLabeledValue(label: $0.label, value: $0.value as NSString)
      }
    }
    if let values = changes.addresses {
      contact.postalAddresses = values.map {
        let address = CNMutablePostalAddress()
        address.street = $0.street ?? ""
        address.city = $0.city ?? ""
        address.state = $0.state ?? ""
        address.postalCode = $0.postalCode ?? ""
        address.country = $0.country ?? ""
        address.isoCountryCode = $0.countryCode?.uppercased() ?? ""
        return CNLabeledValue(label: $0.label, value: address)
      }
    }
    if let value = changes.birthday {
      contact.birthday = DateComponents(
        calendar: Calendar(identifier: .gregorian), year: value.year, month: value.month,
        day: value.day)
    }
    if changes.clear?.contains(.birthday) == true { contact.birthday = nil }
  }
  private static func nonempty(_ value: String) -> String? { value.isEmpty ? nil : value }
  private static func label(_ value: String?) -> String? {
    value
  }
  private static func phones(_ contact: CNContact) -> [ContactValue]? {
    contact.phoneNumbers.isEmpty
      ? nil
      : contact.phoneNumbers.map {
        ContactValue(label: label($0.label), value: $0.value.stringValue)
      }
  }
  private static func values(_ values: [CNLabeledValue<NSString>]) -> [ContactValue]? {
    values.isEmpty
      ? nil : values.map { ContactValue(label: label($0.label), value: $0.value as String) }
  }
  static func summary(_ contact: CNContact) -> ContactSummary {
    let name = [contact.givenName, contact.middleName, contact.familyName].filter { !$0.isEmpty }
      .joined(separator: " ")
    return ContactSummary(
      id: contact.identifier, name: name.isEmpty ? contact.organizationName : name,
      phones: phones(contact), emails: values(contact.emailAddresses))
  }
  static func record(_ contact: CNContact) -> ContactRecord {
    let addresses = contact.postalAddresses.map { entry in
      let value = entry.value
      return ContactAddress(
        label: label(entry.label), street: nonempty(value.street), city: nonempty(value.city),
        state: nonempty(value.state), postalCode: nonempty(value.postalCode),
        country: nonempty(value.country), countryCode: nonempty(value.isoCountryCode))
    }
    let birthday = contact.birthday.flatMap { value -> ContactBirthday? in
      guard let month = value.month, let day = value.day else { return nil }
      return ContactBirthday(month: month, day: day, year: value.year)
    }
    return ContactRecord(
      id: contact.identifier, givenName: nonempty(contact.givenName),
      middleName: nonempty(contact.middleName),
      familyName: nonempty(contact.familyName), prefix: nonempty(contact.namePrefix),
      suffix: nonempty(contact.nameSuffix),
      nickname: nonempty(contact.nickname), organization: nonempty(contact.organizationName),
      department: nonempty(contact.departmentName),
      jobTitle: nonempty(contact.jobTitle), phones: phones(contact),
      emails: values(contact.emailAddresses), urls: values(contact.urlAddresses),
      addresses: addresses.isEmpty ? nil : addresses, birthday: birthday)
  }
}
