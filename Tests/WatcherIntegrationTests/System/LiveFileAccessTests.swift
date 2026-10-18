import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration))
struct LiveFileAccessTests {
    private let files = FileAccess.live
    private let temporary: TemporaryDirectory

    init() throws {
        temporary = try TemporaryDirectory(prefix: "watcher-files")
    }

    @Test
    func foldersFilesAndProgramsAreToldApart() throws {
        let file = temporary.url.appendingPathComponent("a.txt")
        try files.writeAtomically(Data("a".utf8), file)
        #expect(files.isDirectory(temporary.url.path) && !files.isDirectory(file.path))
        #expect(files.fileExists(file.path) && !files.fileExists(file.path + ".missing"))
        #expect(files.isExecutable("/bin/sh") && !files.isExecutable(file.path))
    }

    @Test
    func aMoveNeverReplacesAnExistingFile() throws {
        let source = temporary.url.appendingPathComponent("a"), target = temporary.url.appendingPathComponent("b")
        try files.writeAtomically(Data("a".utf8), source)
        try files.writeAtomically(Data("b".utf8), target)
        #expect(throws: (any Error).self) { try files.move(source, target) }
        #expect(try files.read(target) == Data("b".utf8))
    }

    @Test
    func aPrivateWriteReplacesTheFileWithOneOnlyTheOwnerCanReadAndLeavesNothingBehind() throws {
        let file = temporary.url.appendingPathComponent("secret")
        try files.writeAtomically(Data("old".utf8), file)
        try files.writePrivately(Data("new".utf8), file)
        #expect(try files.read(file) == Data("new".utf8))
        let mode = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        #expect(mode == 0o600)
        #expect(try files.contentsOfDirectory(temporary.url).map(\.lastPathComponent) == ["secret"])
    }

    @Test
    func aPrivateWriteIntoAMissingFolderThrows() {
        let file = temporary.url.appendingPathComponent("none/secret")
        #expect(throws: (any Error).self) { try files.writePrivately(Data(), file) }
    }

    @Test
    func temporaryFilesAreUniqueAndCarryTheirExtension() {
        let first = files.temporaryFile("har"), second = files.temporaryFile("har")
        #expect(first != second)
        #expect(first.pathExtension == "har")
    }

    @Test
    func aMissingFileHasNoModificationDateAndCannotBeRemoved() {
        let missing = temporary.url.appendingPathComponent("missing")
        #expect(files.modificationDate(missing.path) == nil)
        #expect(throws: (any Error).self) { try files.remove(missing) }
    }

    @Test
    func aFolderListsTheFilesDirectlyInsideIt() throws {
        let file = temporary.url.appendingPathComponent("a.workspace")
        try files.writeAtomically(Data(), file)
        try files.createDirectory(temporary.url.appendingPathComponent("nested/deeper"))
        let names = try files.contentsOfDirectory(temporary.url).map(\.lastPathComponent).sorted()
        #expect(names == ["a.workspace", "nested"])
        let missing = temporary.url.appendingPathComponent("none")
        #expect(throws: (any Error).self) { try files.contentsOfDirectory(missing) }
    }
}
