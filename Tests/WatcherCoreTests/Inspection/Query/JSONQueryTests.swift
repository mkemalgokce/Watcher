import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct JSONQueryTests {
    @Test
    func pathsWildcardsAndRecursiveDescentSelectValues() throws {
        let json = Data(
            #"{"users":[{"id":1,"email":"a@x"},{"id":2,"email":"b@x","tags":["t"]}],"meta":{"email":"m@x"}}"#.utf8
        )
        #expect(JSONQuery.run("users[1].id", on: json) == "2")
        #expect(JSONQuery.run("$.users[0].email", on: json) == "\"a@x\"")
        #expect(try #require(JSONQuery.run("users[*].id", on: json)).filter { !$0.isWhitespace } == "[1,2]")
        #expect(try #require(JSONQuery.run("..email", on: json)).filter { !$0.isWhitespace } == #"["m@x","a@x","b@x"]"#)
        #expect(try #require(JSONQuery.run("email", on: json)).filter { !$0.isWhitespace } == #"["m@x","a@x","b@x"]"#)
        #expect(JSONQuery.run("users[9]", on: json) == "")
        #expect(JSONQuery.run("a", on: Data("not json".utf8)) == nil)
    }

    @Test(arguments: [("users[0", "1"), ("users[", ""), ("[", ""), ("users[0].x[", "")])
    func anUnclosedBracketIsReadToTheEndOfTheQuery(query: String, expected: String) {
        #expect(JSONQuery.run(query, on: Data(#"{"users":[1]}"#.utf8)) == expected)
    }
}
