import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CodeBeautifierTests {
    @Test
    func beautifiesCSSAndJS() {
        #expect(CodeBeautifier.beautify("a{color:red;margin:0}") == "a {\n  color:red;\n  margin:0\n}")
        let script = CodeBeautifier.beautify("for(var i=0;i<3;i++){f(\"a;b\",1)}")
        #expect(script.contains("for(var i=0;i<3;i++) {"), "\(script)")
        #expect(script.contains("f(\"a;b\",1)") || script.contains("f(\"a;b\", 1)"), "\(script)")
    }
}
