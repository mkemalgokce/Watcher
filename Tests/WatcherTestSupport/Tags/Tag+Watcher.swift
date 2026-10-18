import Testing

public extension Tag {
    @Tag static var unit: Self
    @Tag static var integration: Self
    // swiftlint:disable:next identifier_name
    @Tag static var ui: Self
    @Tag static var smoke: Self
    @Tag static var e2e: Self
    @Tag static var snapshot: Self
    @Tag static var network: Self
    @Tag static var externalTool: Self
    @Tag static var accessibility: Self
    @Tag static var timing: Self
}
