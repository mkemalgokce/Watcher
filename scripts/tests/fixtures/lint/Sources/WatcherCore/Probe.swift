import Foundation
import SwiftUI

/// Writes a line the way `print(_:)` would, unlike `UserDefaults.standard` or `Color(red:)`.
let documented = "call print(x), UserDefaults.standard, Color(red: 1) and .font(.system(size: 12)) in strings"
func realCalls() {
    print("x")
    _ = UserDefaults.standard
    _ = Color(red: 1, green: 0, blue: 0)
    _ = Font.system(size: 12)
    _ = Text("x").font(.custom("Helvetica", size: 12))
    _ = Color(.sRGB, red: 1, green: 0, blue: 0)
}
