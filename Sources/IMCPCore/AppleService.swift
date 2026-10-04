/// Implemented services, in menu order. Future inventory belongs in docs/PLAN.md.
public enum AppleService: String, CaseIterable, Codable, Identifiable, Sendable {
  case reminders
  case calendar
  case contacts
  case maps
  case photos

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .photos: "Photos"
    case .reminders: "Reminders"
    case .calendar: "Calendar"
    case .contacts: "Contacts"
    case .maps: "Maps"
    }
  }
}
