import Testing
@testable import WatcherCore

/// YAML read by Yams and written out as JSON, so the one tree viewer shows both. Order and types come through as written.
@Suite(.tags(.unit))
struct YAMLDocumentTests {
    private func json(_ yaml: String) -> String? {
        YAMLDocument.json(from: yaml)
    }

    @Test
    func keepsKeyOrder() {
        #expect(json("b: 1\na: 2\nc: 3") == #"{"b":1,"a":2,"c":3}"#)
    }

    @Test
    func nestsMapsAndLists() {
        let yaml = """
        server:
          ports: [80, 443]
          tags:
            - web
            - edge
        """
        #expect(json(yaml) == #"{"server":{"ports":[80,443],"tags":["web","edge"]}}"#)
    }

    @Test
    func readsScalarsAsTheTypeYAMLGivesThem() {
        let yaml = """
        n: 12
        f: 1.5
        t: true
        off: false
        nothing: null
        tilde: ~
        word: hello
        quoted: "123"
        text: 'it''s'
        """
        let expected = #"{"n":12,"f":1.5,"t":true,"off":false,"nothing":null,"tilde":null,"#
            + #""word":"hello","quoted":"123","text":"it's"}"#
        #expect(json(yaml) == expected)
    }

    @Test
    func escapesWhatJSONNeedsEscaped() {
        #expect(json("a: \"line\\nbreak \\\"q\\\"\"") == #"{"a":"line\nbreak \"q\""}"#)
    }

    @Test
    func numbersThatJSONCannotWriteBecomeStrings() {
        #expect(json("a: .inf\nb: .nan") == #"{"a":".inf","b":".nan"}"#)
    }

    @Test
    func resolvesAliasesToTheirAnchors() {
        let yaml = """
        base: &b
          x: 1
        copy: *b
        """
        #expect(json(yaml) == #"{"base":{"x":1},"copy":{"x":1}}"#)
    }

    @Test
    func severalDocumentsBecomeAnArray() {
        #expect(json("a: 1\n---\nb: 2\n") == #"[{"a":1},{"b":2}]"#)
    }

    @Test
    func commentsAreDropped() {
        #expect(json("# top\na: 1 # trailing\n") == #"{"a":1}"#)
    }

    @Test(arguments: ["", "just a sentence", "42", "- [unclosed", "a: b: c", "key: [1, 2", "\t- tab"])
    func refusesWhatIsNotAMapOrAList(text: String) {
        #expect(json(text) == nil)
    }

    @Test
    func aListAtTheTopIsADocument() {
        #expect(json("- a\n- b") == #"["a","b"]"#)
    }

    @Test
    func aDocumentThatAliasesItselfIntoAHugeOutputIsRefused() {
        var yaml = "a0: &a0 [x, x, x, x, x, x, x, x, x, x]\n"
        for level in 1 ... 9 {
            let previous = (0 ..< 10).map { _ in "*a\(level - 1)" }.joined(separator: ", ")
            yaml += "a\(level): &a\(level) [\(previous)]\n"
        }
        #expect(json(yaml) == nil)
    }

    @Test
    func theResultIsAJSONDocumentTheTreeCanRead() throws {
        let text = try #require(json("users:\n  - name: Ada\n    id: 7\n"))
        let tree = try #require(JSONTree.parse(text))
        #expect(tree.nodes.map(\.kind) == [.object, .array, .object, .string, .number])
    }
}
