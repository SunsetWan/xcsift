import XCTest
import XCSiftCore

class BuildPhasesTest: XCTestCase {
    let parser = OutputParser()

    func testPhaseScriptExecutionFailureBasic() {
        let output = """
            /bin/sh -c /Users/dhavalkansara/Library/Developer/Xcode/DerivedData/AFEiOS-gctxucyuhlhesnfkbuxfswkozboo/Build/Intermediates.noindex/AFEiOS.build/Debug-iphoneos/AFEiOS.build/Script-19DAA30A22C0FB0100A039E2.sh
            The path lib/main.dart does not exist
            The path  does not exist
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertNil(error.file, "PhaseScriptExecution error should not have file")
        XCTAssertNil(error.line, "PhaseScriptExecution error should not have line number")
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
        XCTAssertTrue(
            error.message.contains("The path lib/main.dart does not exist"),
            "Error message should include context from preceding lines"
        )
    }

    func testPhaseScriptExecutionPrioritizesFlutterProcessExceptionOverTrailingStackFrames() {
        let output = """
            PhaseScriptExecution [CP-User] Run Flutter Build hc_flutter_module Script /tmp/DerivedData/Script.sh (in target 'HikConnect' from project 'VideoGo')
            ♦ /Users/example/flutter/bin/flutter --verbose assemble -dTargetFile=lib/main.dart
            Unhandled exception:
            ProcessException: No such file or directory
              Command: /Users/example/flutter/bin/flutter --verbose assemble -dTargetFile=lib/main.dart
            #0      _ProcessImpl._runAndWait (dart:io-patch/process_patch.dart:509:7)
            #7      main (file:///Users/example/flutter/packages/flutter_tools/bin/xcode_backend.dart:17:5)
            #8      _delayEntrypointInvocation.<anonymous closure> (dart:isolate-patch/isolate_patch.dart:311:33)
            #9      _RawReceivePort._handleMessage (dart:isolate-patch/isolate_patch.dart:192:12)
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertNil(result.errors.first?.file)
        XCTAssertNil(result.errors.first?.line)
        XCTAssertEqual(
            result.errors.first?.message,
            "[CP-User] Run Flutter Build hc_flutter_module Script: ProcessException: No such file or directory; Command: /Users/example/flutter/bin/flutter --verbose assemble -dTargetFile=lib/main.dart"
        )
    }

    func testPhaseScriptExecutionRedactsSensitiveCommandArguments() {
        let output = """
            PhaseScriptExecution Run\\ Secret\\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: command failed
              Command: /usr/bin/tokenizer input.json --token top-secret --dart-define=API_KEY=another-secret DART_DEFINES=encoded-secret https://user:pass@example.com/path?token=query-secret&mode=debug
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)
        let message = try? XCTUnwrap(result.errors.first?.message)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("/usr/bin/tokenizer input.json") == true)
        XCTAssertTrue(message?.contains("<redacted>") == true)
        for secret in ["top-secret", "another-secret", "encoded-secret", "user:pass", "query-secret"] {
            XCTAssertFalse(message?.contains(secret) == true, "Leaked secret: \(secret)")
        }
    }

    func testPhaseScriptExecutionRedactsQuotedEscapedAndHeaderArguments() {
        let output = #"""
            PhaseScriptExecution Run\ Secret\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: command failed
              Command: /usr/bin/tool --password "quoted-value alpha" --token escaped-head\ escaped-tail-value --header=Authorization:Bearer-header-value -H "Cookie: cookie-header-value" -dDartDefines=dart-defines-value output.json
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """#

        let result = parser.parse(input: output)
        let message = try? XCTUnwrap(result.errors.first?.message)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("/usr/bin/tool") == true)
        XCTAssertTrue(message?.contains("output.json") == true)
        XCTAssertTrue(message?.contains("<redacted>") == true)
        for secret in [
            "quoted-value", "alpha", "escaped-head", "escaped-tail-value", "header-value",
            "cookie-header-value", "dart-defines-value",
        ] {
            XCTAssertFalse(message?.contains(secret) == true, "Leaked secret: \(secret)")
        }
    }

    func testPhaseScriptExecutionRedactsColonValuesAndStandaloneHeaders() {
        let output = #"""
            PhaseScriptExecution Run\ Secret\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: command failed
              Command: /usr/bin/tool --password:colon-attached-value -h output.json "Authorization: Bearer standalone-header-value" Authorization: \Bearer escaped-scheme-secret keep.txt
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """#

        let result = parser.parse(input: output)
        let message = try? XCTUnwrap(result.errors.first?.message)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("-h output.json") == true)
        XCTAssertTrue(message?.contains("keep.txt") == true)
        XCTAssertTrue(message?.contains("<redacted>") == true)
        for secret in [
            "colon-attached-value", "standalone-header-value", "escaped-scheme-secret",
        ] {
            XCTAssertFalse(message?.contains(secret) == true, "Leaked secret: \(secret)")
        }
    }

    func testPhaseScriptExecutionRedactsQuotedAndEscapedSensitiveOptionNames() {
        let output = #"""
            PhaseScriptExecution Run\ Secret\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: command failed
              Command: /usr/bin/tool "--password" quoted-option-secret '--token' single-quoted-option-secret \--apikey escaped-option-secret "--password=quoted-attached-secret" keep.txt
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """#

        let result = parser.parse(input: output)
        let message = try? XCTUnwrap(result.errors.first?.message)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("keep.txt") == true)
        XCTAssertTrue(message?.contains("<redacted>") == true)
        for secret in [
            "quoted-option-secret", "single-quoted-option-secret", "escaped-option-secret",
            "quoted-attached-secret",
        ] {
            XCTAssertFalse(message?.contains(secret) == true, "Leaked secret: \(secret)")
        }
    }

    func testPhaseScriptExecutionRedactsEscapedURLCredentials() {
        let output = #"""
            PhaseScriptExecution Run\ Secret\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: command failed
              Command: /usr/bin/tool https:/\/escaped-user:escaped-slash-secret@example.com/path --endpoint=https:/\/endpoint-user:endpoint-secret@example.com/api https://example.com/callback#access_token=fragment-secret&mode=debug keep.txt
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """#

        let result = parser.parse(input: output)
        let message = try? XCTUnwrap(result.errors.first?.message)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("keep.txt") == true)
        XCTAssertTrue(message?.contains("<redacted>@example.com") == true)
        for secret in [
            "escaped-user", "escaped-slash-secret", "endpoint-user", "endpoint-secret",
            "fragment-secret",
        ] {
            XCTAssertFalse(message?.contains(secret) == true, "Leaked secret: \(secret)")
        }
    }

    func testPhaseScriptExecutionFlushesConfirmedFailureWithoutGenericTerminator() {
        let output = """
            PhaseScriptExecution [CP-User] Run Flutter Build /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: No such file or directory
              Command: /Users/example/flutter/bin/flutter assemble
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(
            result.errors.first?.message,
            "[CP-User] Run Flutter Build: ProcessException: No such file or directory; Command: /Users/example/flutter/bin/flutter assemble"
        )
    }

    func testPhaseScriptExecutionFreezesFailureBeforeTrailingBuildSummary() {
        let output = """
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: No such file or directory
              Command: /Users/example/flutter/bin/flutter assemble
            ** BUILD FAILED **

            The following build commands failed:
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            (1 failure)
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(
            result.errors.first?.message.contains("ProcessException: No such file or directory") == true
        )
        XCTAssertTrue(result.errors.first?.message.contains("Command: /Users/example/flutter") == true)
    }

    func testPhaseScriptExecutionFlushesExplicitExceptionAtEOF() {
        let output = """
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: No such file or directory
              Command: /Users/example/flutter/bin/flutter assemble
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(
            result.errors.first?.message,
            "Run Flutter: ProcessException: No such file or directory; Command: /Users/example/flutter/bin/flutter assemble"
        )
    }

    func testPhaseScriptExecutionDoesNotTreatCommandOnlyEOFAsFailure() {
        let output = """
            PhaseScriptExecution Generate\\ Metadata /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
              Command: /usr/bin/generate-metadata --output /tmp/result.json
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "incomplete")
        XCTAssertEqual(result.summary.errors, 0)
    }

    func testPhaseScriptExecutionDiscardsPendingExceptionAtSuccessBoundary() {
        let output = """
            PhaseScriptExecution Retryable\\ Script /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: transient first-attempt failure
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
    }

    func testPhaseScriptExecutionDiscardsPendingExceptionAtTestFailureBoundary() {
        let output = """
            PhaseScriptExecution Retryable\\ Script /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: transient setup retry
            ** TEST FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 0)
    }

    func testPhaseScriptExecutionDiscardsPendingExceptionAtTestExecuteFailureBoundary() {
        let output = """
            PhaseScriptExecution Retryable\\ Script /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: transient setup retry
            ** TEST EXECUTE FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 0)
    }

    func testPhaseScriptExecutionKeepsContextsIsolatedAcrossPhases() {
        let output = """
            PhaseScriptExecution First\\ Script /tmp/DerivedData/First.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: stale failure from first phase
              Command: /usr/bin/first-tool
            PhaseScriptExecution Second\\ Script /tmp/DerivedData/Second.sh (in target 'MyApp' from project 'MyApp')
            /tmp/Second.sh: line 4: missing-second-tool: command not found
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("Second Script") == true)
        XCTAssertTrue(message?.contains("missing-second-tool: command not found") == true)
        XCTAssertFalse(message?.contains("stale failure") == true)
        XCTAssertFalse(message?.contains("first-tool") == true)
        XCTAssertFalse(message?.contains(XcodebuildSymbolsForTests.genericScriptFailure) == true)
    }

    func testPhaseScriptExecutionEndsAtNonScriptBuildPhase() {
        let output = """
            PhaseScriptExecution Retryable\\ Script /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: handled retry from completed script
            CompileSwiftSources normal arm64 com.apple.xcode.tools.swift.compiler (in target 'MyApp' from project 'MyApp')
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 0)
    }

    func testPhaseScriptExecutionEndsAtSwiftDriverBuildPhase() {
        let output = """
            PhaseScriptExecution Retryable\\ Script /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: handled retry from completed script
            SwiftDriver\\ Compilation MyApp normal arm64 com.apple.xcode.tools.swift.compiler (in target 'MyApp' from project 'MyApp')
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 0)
    }

    func testPhaseScriptExecutionEndsAtUnlistedXcodeBuildCommand() {
        let output = """
            PhaseScriptExecution Retryable\\ Script /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: handled retry from completed script
            SwiftCompile normal arm64 /workspace/App.swift (in target 'MyApp' from project 'MyApp')
            /workspace/App.swift:7:3: error: separate compiler failure
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(result.errors.first?.message.contains("separate compiler failure") == true)
        XCTAssertFalse(result.errors.first?.message.contains("handled retry") == true)
    }

    func testPhaseScriptExecutionKeepsContextAcrossNestedSPMOutput() {
        let output = """
            PhaseScriptExecution Run\\ Nested\\ Build /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: nested package command failed
            [1/2] Compiling NestedHelper
            [2/2] Linking NestedHelper
            nested output 1
            nested output 2
            nested output 3
            nested output 4
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(
            result.errors.first?.message.contains("ProcessException: nested package command failed") == true
        )
        XCTAssertFalse(result.errors.first?.message.contains("nested output 2") == true)
    }

    func testPhaseScriptExecutionFindsUnpunctuatedFailureMarkerAnywhereInLine() {
        let output = """
            PhaseScriptExecution Run\\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            failed to launch because No such file or directory
            tail output 1
            tail output 2
            tail output 3
            tail output 4
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(
            result.errors.first?.message.contains("failed to launch because No such file or directory")
                == true
        )
        XCTAssertFalse(result.errors.first?.message.contains("tail output 2") == true)
    }

    func testPhaseScriptExecutionTreatsScriptEvidenceAsEvidenceBeforePhaseBoundary() {
        let output = """
            PhaseScriptExecution Run\\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            Error: generator failed while processing (in target 'Nested')
            tail output 1
            tail output 2
            tail output 3
            tail output 4
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(
            result.errors.first?.message.contains(
                "Error: generator failed while processing (in target 'Nested')"
            ) == true
        )
        XCTAssertFalse(result.errors.first?.message.contains("tail output 2") == true)
    }

    func testPhaseScriptExecutionKeepsPrimaryAlongsideInterleavedStructuredError() {
        let output = """
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: flutter tool failed independently
            /workspace/Other.swift:7:3: error: separate compiler failure
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 2)
        XCTAssertTrue(result.errors.contains { $0.message.contains("separate compiler failure") })
        XCTAssertTrue(result.errors.contains { $0.message.contains("flutter tool failed independently") })
    }

    func testPhaseScriptExecutionTreatsCommandTextAsCommandBeforeFailureCandidate() {
        let output = #"""
            PhaseScriptExecution Run\ Shell /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: shell wrapper failed
              Command: /bin/sh -c "echo No such file or directory"
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """#

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("ProcessException: shell wrapper failed") == true)
        XCTAssertTrue(message?.contains("Command: /bin/sh -c") == true)
        XCTAssertTrue(message?.contains("echo No such file or directory") == true)
    }

    func testPhaseScriptExecutionPrioritizesDartCompilerErrorOverKernelSnapshotWrapper() {
        let output = """
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            lib/main.dart:18:12: Error: Method not found: 'missingMethod'.
            Target kernel_snapshot_program failed: Exception
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("lib/main.dart:18:12: Error: Method not found") == true)
        XCTAssertFalse(message?.contains("Target kernel_snapshot_program failed") == true)
        XCTAssertFalse(message?.contains(XcodebuildSymbolsForTests.genericScriptFailure) == true)
    }

    func testPhaseScriptExecutionKeepsFirstDartCompilerErrorAtEqualPriority() {
        let output = """
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            lib/first.dart:10:4: Error: First actionable compiler failure.
            lib/second.dart:20:8: Error: Secondary cascading failure.
            Target kernel_snapshot_program failed: Exception
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("First actionable compiler failure") == true)
        XCTAssertFalse(message?.contains("Secondary cascading failure") == true)
    }

    func testPhaseScriptExecutionExtractsRubyNodeAndPythonFailures() {
        let cases = [
            (
                line: "LoadError: cannot load such file -- cocoapods",
                expected: "LoadError: cannot load such file -- cocoapods"
            ),
            (
                line: "FileSystemException: Cannot open file, path = '/tmp/config.json'",
                expected: "FileSystemException: Cannot open file"
            ),
            (
                line: "MODULE_NOT_FOUND: Cannot find module 'vite'",
                expected: "MODULE_NOT_FOUND: Cannot find module 'vite'"
            ),
            (
                line: "ModuleNotFoundError: No module named 'yaml'",
                expected: "ModuleNotFoundError: No module named 'yaml'"
            ),
        ]

        for item in cases {
            let output = """
                PhaseScriptExecution Run\\ Tool /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
                \(item.line)
                Command PhaseScriptExecution failed with a nonzero exit code
                ** BUILD FAILED **
                """
            let result = parser.parse(input: output)

            XCTAssertEqual(result.summary.errors, 1, item.line)
            XCTAssertTrue(result.errors.first?.message.contains(item.expected) == true, item.line)
            XCTAssertFalse(
                result.errors.first?.message.contains(XcodebuildSymbolsForTests.genericScriptFailure) == true,
                item.line
            )
        }
    }

    func testPhaseScriptExecutionExtractsFinalPythonTracebackMessage() {
        let output = """
            PhaseScriptExecution Run\\ Python /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            Traceback (most recent call last):
              File "/workspace/build.py", line 8, in <module>
                import yaml
            ModuleNotFoundError: No module named 'yaml'
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("ModuleNotFoundError: No module named 'yaml'") == true)
        XCTAssertFalse(message?.contains("build.py") == true)
        XCTAssertFalse(message?.contains("Traceback") == true)
    }

    func testPhaseScriptExecutionCombinesNodeModuleTypeWithPrimaryMessage() {
        let output = """
            PhaseScriptExecution Run\\ Node /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            Error: Cannot find module 'vite'
                at Module._resolveFilename (node:internal/modules/cjs/loader:1144:15)
              code: 'MODULE_NOT_FOUND'
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("Error: Cannot find module 'vite'") == true)
        XCTAssertTrue(message?.contains("MODULE_NOT_FOUND") == true)
        XCTAssertFalse(message?.contains(XcodebuildSymbolsForTests.genericScriptFailure) == true)
    }

    func testPhaseScriptExecutionWarningDoesNotDisplacePrimaryFailure() {
        let output = """
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: No such file or directory
            /workspace/generated.swift:3:2: warning: generated fallback will be removed
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output, printWarnings: true)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertTrue(result.errors.first?.message.contains("ProcessException: No such file or directory") == true)
        XCTAssertFalse(result.errors.first?.message.contains("generated fallback") == true)
    }

    func testPhaseScriptExecutionIgnoresLargeStackWhenSelectingSummary() {
        let stack = (0 ..< 2_000).map {
            "#\($0) frame (file:///flutter/packages/flutter_tools/bin/xcode_backend.dart:\($0):7)"
        }.joined(separator: "\n")
        let output = """
            PhaseScriptExecution Run\\ Flutter /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            ProcessException: No such file or directory
              Command: /usr/bin/flutter assemble
            \(stack)
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("ProcessException: No such file or directory") == true)
        XCTAssertFalse(message?.contains("#1999") == true)
        XCTAssertLessThanOrEqual(message?.utf8.count ?? .max, 4_700)
    }

    func testPhaseScriptExecutionDoesNotReuseStaleImplicitException() {
        let unrelatedLines = (0 ..< 20).map { "unrelated output \($0)" }.joined(separator: "\n")
        let output = """
            Error: unrelated failure from an earlier tool
            \(unrelatedLines)
            /bin/sh -c /tmp/current-script.sh
            current script failed without details
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)
        let message = result.errors.first?.message

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertTrue(message?.contains("current script failed without details") == true)
        XCTAssertFalse(message?.contains("earlier tool") == true)
    }

    func testPhaseScriptExecutionWithHermesFramework() {
        let output = """
            Run script build phase '[CP-User] [Hermes] Replace Hermes for the right configuration, if needed' will be run during every build because it does not specify any outputs. To address this warning, either add output dependencies to the script phase, or configure it to run in every build by unchecking "Based on dependency analysis" in the script phase.
            PhaseScriptExecution [CP-User]\\ [Hermes]\\ Replace\\ Hermes\\ for\\ the\\ right\\ configuration,\\ if\\ needed /Library/Developer/Xcode/DerivedData/myProjectName-gzdlehmipieiindfjyfrhhcjupam/Build/Intermediates.noindex/ArchiveIntermediates/myProjectName/IntermediateBuildFilesPath/Pods.build/Release-iphoneos/hermes-engine.build/Script-46EB2E0002C950.sh (in target 'hermes-engine' from project 'Pods')
            Node found at: /var/folders/d5/f1gffcfx27ngwvmw8v8jdm7m0000gn/T/yarn--1704767526546-0.12516067745295967/node
            /Library/Developer/Xcode/DerivedData/myProjectName-gzdlehmipieiindfjyfrhhcjupam/Build/Intermediates.noindex/ArchiveIntermediates/myProjectName/IntermediateBuildFilesPath/Pods.build/Release-iphoneos/hermes-engine.build/Script-46EB2E0002C950.sh: line 9: /var/folders/d5/f1gffcfx27ngwvmw8v8jdm7m0000gn/T/yarn--1704767526546-0.12516067745295967/node: No such file or directory
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure for Hermes")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("[CP-User] [Hermes] Replace Hermes for the right configuration, if needed"),
            "Error message should identify the failing phase"
        )
        XCTAssertTrue(
            error.message.contains("No such file or directory"),
            "Error message should include context about missing file"
        )
    }

    func testPhaseScriptExecutionWithUnityGameAssembly() {
        let output = """
            /bin/sh -c /Users/evgeniyasenchurova/Library/Developer/Xcode/DerivedData/Unity-iPhone-gtnilxmbqexxvtcauewfdmpfbvfe/Build/Intermediates.noindex/ArchiveIntermediates/Unity-iPhone/IntermediateBuildFilesPath/Unity-iPhone.build/Release-iphoneos/GameAssembly.build/Script-C62A2A42F32E085EF849CF0B.sh
            /Users/evgeniyasenchurova/Library/Developer/Xcode/DerivedData/Unity-iPhone-gtnilxmbqexxvtcauewfdmpfbvfe/Build/Intermediates.noindex/ArchiveIntermediates/Unity-iPhone/IntermediateBuildFilesPath/Unity-iPhone.build/Release-iphoneos/GameAssembly.build/Script-C62A2A42F32E085EF849CF0B.sh: line 19: /Users/evgeniyasenchurova Downloads/ build_ios/Il2Cpp0utputProject/IL2CPP/build/deploy_arm64/il2cpp: Operation not permitted
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure for Unity")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Operation not permitted"),
            "Error message should include operation permission error"
        )
        XCTAssertTrue(error.message.contains(XcodebuildSymbolsForTests.genericScriptFailure))
    }

    func testPhaseScriptExecutionWithMultipleErrors() {
        let output = """
            Build started...

            Compiling Swift files...
            file.swift:10: error: Cannot find 'someFunction' in scope

            Running post-build script...
            /bin/sh -c /path/to/script.sh
            Script execution failed
            Command PhaseScriptExecution failed with a nonzero exit code

            Build complete!
            """

        let result = parser.parse(input: output)

        // Should detect both the compilation error and the PhaseScriptExecution failure
        XCTAssertEqual(
            result.summary.errors,
            2,
            "Should detect both compilation error and PhaseScriptExecution failure"
        )

        // Find the PhaseScriptExecution error
        let phaseError = result.errors.first { $0.message.contains("Command PhaseScriptExecution failed") }
        XCTAssertNotNil(phaseError, "Should have PhaseScriptExecution error")

        if let phaseError = phaseError {
            XCTAssertTrue(
                phaseError.message.contains("Script execution failed"),
                "Error message should include preceding context"
            )
        }
    }

    func testPhaseScriptExecutionDoesNotAddGenericErrorAfterActionableScriptError() {
        let output = """
            PhaseScriptExecution Run\\ Custom\\ Validation /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            /workspace/validate.swift:42:7: error: Invalid generated configuration
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.first?.file, "/workspace/validate.swift")
        XCTAssertEqual(result.errors.first?.line, 42)
        XCTAssertEqual(result.errors.first?.message, "Invalid generated configuration")
    }

    func testPhaseScriptExecutionKeepsMultipleIndependentActionableErrors() {
        let output = """
            PhaseScriptExecution Run\\ Validation /tmp/DerivedData/Script.sh (in target 'MyApp' from project 'MyApp')
            /workspace/first.swift:4:2: error: First invalid generated value
            /workspace/second.swift:8:6: error: Second invalid generated value
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 2)
        XCTAssertEqual(result.errors.map(\.file), ["/workspace/first.swift", "/workspace/second.swift"])
        XCTAssertFalse(result.errors.contains { $0.message.contains(XcodebuildSymbolsForTests.genericScriptFailure) })
    }

    func testPhaseScriptExecutionWithSingleLineContext() {
        let output = """
            Running build phase script...
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure with single context line")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
        XCTAssertTrue(
            error.message.contains("Running build phase script"),
            "Error message should include context line"
        )
    }

    func testPhaseScriptExecutionWithNoContext() {
        let output = """
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure even with no context")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
    }

    func testPhaseScriptExecutionDoesNotDuplicateErrors() {
        let output = """
            /bin/sh -c /path/to/script.sh
            Command PhaseScriptExecution failed with a nonzero exit code
            /bin/sh -c /path/to/script.sh
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        // Should deduplicate identical errors
        XCTAssertLessThanOrEqual(
            result.summary.errors,
            2,
            "Should not duplicate identical PhaseScriptExecution errors"
        )
    }

    func testBuildSucceededDoesNotCreatePhaseError() {
        let output = """
            Running phase script...
            Build succeeded in 5.234 seconds
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 0, "Build succeeded should not create a PhaseScriptExecution error")
    }

    func testPhaseScriptExecutionWithComplexOutput() {
        let output = """
            ** BUILD START **

            Linking Framework/Module

            Running script phase [CP] Copy Pods Resources

            Resources copied...
            warning: Some resources were skipped

            Running script phase custom build script

            Processing configuration...
            /bin/sh -c /path/to/complex/script.sh
            Error: Configuration file not found at /expected/path
            Command PhaseScriptExecution failed with a nonzero exit code

            Build failed after 10.234 seconds
            """

        let result = parser.parse(input: output)

        // Should detect the actionable script error rather than the generic phase wrapper.
        let phaseError = result.errors.first { $0.message.contains("Configuration file not found") }
        XCTAssertNotNil(phaseError, "Should detect PhaseScriptExecution failure in complex output")

        if let phaseError = phaseError {
            XCTAssertTrue(
                phaseError.message.contains("Error: Configuration file not found"),
                "Should include relevant context from preceding lines"
            )
            XCTAssertTrue(phaseError.message.contains(XcodebuildSymbolsForTests.genericScriptFailure))
        }
    }

    func testPhaseScriptExecutionFiltersUnrelatedWarnings() {
        // Test case based on user's real project scenario
        let output = """
            Warning: unknown environment variable SWIFT_DEBUG_INFORMATION_FORMAT
            bash: /Users/roman/Developer/SpaceTime/build_id.sh: No such file or directory
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("bash:"),
            "Error message should include bash error context"
        )
        XCTAssertTrue(
            error.message.contains("No such file or directory"),
            "Error message should include error details"
        )
        XCTAssertFalse(
            error.message.contains("Warning: unknown environment variable"),
            "Should filter out unrelated Warning: lines"
        )
        XCTAssertTrue(error.message.contains(XcodebuildSymbolsForTests.genericScriptFailure))
    }
}

private enum XcodebuildSymbolsForTests {
    static let genericScriptFailure = "Command PhaseScriptExecution failed"
}
