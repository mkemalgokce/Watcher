import Foundation
import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct KeyLogFileTests {
    private let files = FileAccessFake()

    @Test
    func aNewFileIsCreatedReadableByItsOwnerAlone() throws {
        _ = try #require(KeyLogFile(path: "/logs/keys.log", files: files.access))
        #expect(files.contents(of: "/logs/keys.log") == Data())
        #expect(files.permissionHistory(of: "/logs/keys.log") == [0o600])
    }

    @Test
    func eachSecretIsAppendedAsALineAfterWhatTheFileHeld() throws {
        files.write(Data("old\n".utf8), to: "/logs/keys.log")
        let log = try #require(KeyLogFile(path: "/logs/keys.log", files: files.access))
        log.callback(ByteBuffer(string: "CLIENT_RANDOM a b"))
        log.callback(ByteBuffer(string: "CLIENT_RANDOM c d"))
        #expect(files.contents(of: "/logs/keys.log") == Data("old\nCLIENT_RANDOM a b\nCLIENT_RANDOM c d\n".utf8))
    }

    @Test
    func aFileThatCannotBeWrittenGivesNoLog() {
        files.fail(.appendPrivately)
        #expect(KeyLogFile(path: "/logs/keys.log", files: files.access) == nil)
    }
}
