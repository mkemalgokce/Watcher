import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CodeGeneratorTests {
    @Test
    func newerLanguagesEscapeInterpolationSyntax() {
        let request = Flow.annotatedJSONPostFixture().request
        let golang = CodeGenerator.generate(request, as: .go)
        #expect(
            golang.contains("http.NewRequest(\"POST\", \"https://api.example.com/v1/x?a=1,2\"")
                && golang.contains("req.Header.Set(\"Content-Type\"")
        )
        let ruby = CodeGenerator.generate(request, as: .ruby)
        #expect(ruby.contains("Net::HTTP::Post.new(uri)") && ruby.contains("it's \\#1"), "\(ruby)")
        let injection = RequestRecord.fixture(host: "a", body: Data("#{system('x')}".utf8))
        #expect(CodeGenerator.generate(injection, as: .ruby).contains("\\#{system"))
        let php = CodeGenerator.generate(
            RequestRecord.fixture(method: "POST", host: "a", body: Data("$x 'q'".utf8)),
            as: .php
        )
        #expect(php.contains(#"CURLOPT_POSTFIELDS, '$x \'q\''"#), "\(php)")
        #expect(CodeGenerator.Language.allCases.count == 7)
    }

    @Test
    func curlCommandNamesTheProxyOnlyWhenGiven() {
        let request = RequestRecord.fixture(host: "a.com")
        #expect(
            CodeGenerator.generate(request, as: .curl, proxy: "http://127.0.0.1:9090")
                .contains("-x 'http://127.0.0.1:9090'")
        )
        #expect(!CodeGenerator.generate(request, as: .curl).contains(" -x "))
    }
}
