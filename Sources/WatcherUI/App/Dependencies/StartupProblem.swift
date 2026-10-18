import Foundation

/// The data folder the engine could not open, and what the user is told about it.
struct StartupProblem: Equatable {
    let message: String
    let folder: URL
}
