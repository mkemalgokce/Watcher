import Testing
@testable import WatcherCore

@Suite(.tags(.unit))
struct WildcardTests {
    @Test(arguments: [
        ("*", "", true), ("*", "anything at all", true), ("a*c", "abbbc", true), ("a*c", "ac", true),
        ("a*c", "abd", false), ("*.example.com", "api.example.com", true), ("*.example.com", "example.com", false),
        ("HELLO", "hello", true), ("hello", "HeLLo", true), ("h?llo", "hello", true), ("h?llo", "hllo", false),
        ("h?llo", "heello", false), ("???", "abc", true), ("???", "ab", false),
        ("", "", true), ("", "x", false),
        ("hello", "hello world", false), ("hello", "say hello", false),
    ] as [(String, String, Bool)])
    func aPatternMatchesTheWholeTextIgnoringCase(pattern: String, text: String, matches: Bool) {
        #expect(Wildcard(pattern).matches(text) == matches)
    }

    @Test(arguments: [
        ("a.c", "a.c", true), ("a.c", "abc", false), ("a+b", "a+b", true), ("a+b", "aab", false),
        ("(x)", "(x)", true), ("(x)", "x", false), ("[ab]", "[ab]", true), ("[ab]", "a", false),
        ("^a$", "^a$", true), ("^a$", "a", false), ("a|b", "a|b", true), ("a|b", "a", false),
        ("a{2}", "a{2}", true), ("a{2}", "aa", false), ("a\\b", "a\\b", true),
    ] as [(String, String, Bool)])
    func regexCharactersInAPatternAreLiteral(pattern: String, text: String, matches: Bool) {
        #expect(Wildcard(pattern).matches(text) == matches)
    }

    @Test
    func aStarSpansSlashesAndNewlinesOnlyWhereTheTextAllows() {
        #expect(Wildcard("a*z").matches("a/b/c/z"))
        #expect(Wildcard("a?z").matches("a/z"))
    }
}
