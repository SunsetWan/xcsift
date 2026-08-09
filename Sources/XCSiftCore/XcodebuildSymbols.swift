// MARK: - xcodebuild/SPM Parsing Constants

/// String constants for raw xcodebuild and SPM output patterns.
/// Extracted from inline literals to reduce duplication and improve discoverability.
enum XcodebuildSymbols {
    // Diagnostic format patterns (used in parseError/parseWarning)
    static let errorFormat = ": error: "
    static let warningFormat = ": warning: "
    static let fatalErrorFormat = ": Fatal error: "
    static let fatalErrorSuffix = ": Fatal error"

    // Runtime log noise (os_log/NSLog output that embeds `: error:`/`: warning:` but is not a diagnostic)
    static let coreDataLogPrefix = "CoreData: "

    // Fast-path filter keywords
    static let errorKeyword = "error:"
    static let warningKeyword = "warning:"
    static let fatalErrorKeyword = "Fatal error"
    static let passedKeyword = "passed"
    static let failedKeyword = "failed"
    static let startedSuffix = "' started"
    static let recordedIssue = "recorded an issue"
    static let signalCode = "signal code "
    static let restartingAfter = "Restarting after"

    // Test patterns
    static let testCasePrefix = "Test Case '"
    static let testCaseLowerPrefix = "Test case '"  // parallel testing format
    static let testPassedSuffix = "' passed ("
    static let testFailedSuffix = "' failed ("
    static let testPassedOnSuffix = "' passed on '"
    static let testFailedOnSuffix = "' failed on '"
    static let testSuitePrefix = "Test Suite '"
    static let testSuiteLowerPrefix = "Test suite '"
    static let testSuiteStartedSuffix = "' started"
    static let testSuitePassedMarker = " passed"
    static let testSuiteFailedMarker = " failed"
    static let selectedTestsSuite = "Selected tests"

    // Swift Testing symbols (macOS Private Use Area + Linux fallback)
    static let swiftTestingPass = "✓"
    static let swiftTestingFail = "✘"
    static let swiftTestingStartedPrefix = "◇ Test "
    static let swiftTestingRunStarted = "◇ Test run started."
    static let emojiError = "❌"
    // U+100135 (macOS PUA) / U+21B3 (Linux) — carries #expect custom comment on the line after recorded-issue
    static let swiftTestingDetailsPrefix = "􀄵"
    static let swiftTestingDetailsPrefixFallback = "↳"

    // Build status
    static let buildSucceeded = "** BUILD SUCCEEDED **"
    static let buildFailed = "** BUILD FAILED **"
    static let buildFailedKeyword = "BUILD FAILED"
    static let succeededKeyword = "SUCCEEDED"
    static let testFailed = "TEST FAILED"
    static let testSucceeded = "** TEST SUCCEEDED **"
    static let testExecuteSucceeded = "** TEST EXECUTE SUCCEEDED **"
    static let testExecuteFailed = "** TEST EXECUTE FAILED **"
    static let buildComplete = "Build complete!"
    static let buildSucceededInPrefix = "Build succeeded in "
    static let buildFailedAfterPrefix = "Build failed after "
    static let secondsKeyword = " seconds"

    // Script phase failures
    static let phaseScriptExecutionPrefix = "PhaseScriptExecution "
    static let phaseScriptExecutionFailed = "Command PhaseScriptExecution failed with a nonzero exit"
    static let processExceptionPrefix = "ProcessException:"
    static let fileSystemExceptionPrefix = "FileSystemException:"
    static let loadErrorPrefix = "LoadError:"
    static let loadErrorMarker = "(LoadError)"
    static let moduleNotFound = "MODULE_NOT_FOUND"
    static let commandNotFound = "command not found"
    static let noSuchFileOrDirectory = "No such file or directory"
    static let operationNotPermitted = "Operation not permitted"
    static let dartFileMarker = ".dart:"
    static let dartErrorMarker = ": Error:"
    static let toolErrorPrefix = "Error:"
    static let toolFatalPrefix = "fatal:"
    static let namedExceptionSuffix = "Exception:"
    static let scriptTargetPrefix = "Target "
    static let failedInfix = " failed"
    static let unhandledException = "Unhandled exception:"
    static let tracebackPrefix = "Traceback (most recent call last)"
    static let commandPrefix = "Command:"

    // Build phase prefixes
    static let compileSwiftSourcesPrefix = "CompileSwiftSources "
    static let compileCPrefix = "CompileC "
    static let linkPrefix = "Ld "
    static let copySwiftLibsPrefix = "CopySwiftLibs "
    static let linkAssetCatalogPrefix = "LinkAssetCatalog "
    static let processInfoPlistPrefix = "ProcessInfoPlistFile "

    // File extensions
    static let swiftFilePattern = ".swift:"
    static let objectFileExt = ".o"
    static let archiveFileExt = ".a"
    static let appBundleExt = ".app"

    // Linker patterns
    static let undefinedSymbols = "Undefined symbols for architecture "
    static let referencedFrom = "\", referenced from:"
    static let frameworkNotFound = "ld: framework not found "
    static let libraryNotFound = "ld: library not found for "
    static let duplicateSymbolSingle = "duplicate symbol '"
    static let duplicateSymbolDouble = "duplicate symbol \""

    // Executable / target patterns
    static let registerWithLaunchServices = "RegisterWithLaunchServices"
    static let validate = "Validate"
    static let inTarget = "(in target '"
    static let swiftDriverPrefix = "SwiftDriver"
    static let compilationKeyword = "Compilation"

    // Dependency graph
    static let targetPrefix = "Target '"
    static let dependencyOnTarget = "dependency on target '"

    // SPM phases
    static let spmCompiling = "] Compiling "
    static let spmLinking = "] Linking "
}
