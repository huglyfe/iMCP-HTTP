/// The intended service inventory. Inclusion does not mean an adapter is implemented
/// or that the owner has granted access.
public enum AppleService: String, CaseIterable, Identifiable, Sendable {
  case reminders
  case calendar
  case contacts
  case location
  case maps
  case messages
  case phone
  case shortcuts
  case weather
  case capture
  case utilities

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .reminders: "Reminders"
    case .calendar: "Calendar"
    case .contacts: "Contacts"
    case .location: "Location"
    case .maps: "Maps"
    case .messages: "Messages"
    case .phone: "Phone"
    case .shortcuts: "Shortcuts"
    case .weather: "Weather"
    case .capture: "Capture"
    case .utilities: "Utilities"
    }
  }
}
