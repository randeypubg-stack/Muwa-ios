import Foundation

enum MuwaText {
  static func trackCount(_ count: Int) -> String {
    let hundred = count % 100
    let ending: String
    if (11...14).contains(hundred) { ending = "нашидов" }
    else if count % 10 == 1 { ending = "нашид" }
    else if (2...4).contains(count % 10) { ending = "нашида" }
    else { ending = "нашидов" }
    return "\(count) \(ending)"
  }
}
