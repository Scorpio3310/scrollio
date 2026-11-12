//
//  ReleaseReadinessTests.swift
//  ScrollioTests
//
//  What the repository and the app must carry while they are public: the licence with its
//  notices, the acknowledgements, and build scripts that still do what the documents say.
//  These tests read files. Nothing is built, signed or uploaded here, and
//  `scripts/release.sh` is never run.
//

import XCTest
@testable import Scrollio_Debug

final class ReleaseReadinessTests: XCTestCase {

    /// The repository, found from this file: ScrollioTests/ReleaseReadinessTests.swift.
    private static let root = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func text(_ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let url = Self.root.appendingPathComponent(path)
        return try XCTUnwrap(try? String(contentsOf: url, encoding: .utf8), "cannot read \(path)", file: file, line: line)
    }

    /// The lines of a shell script that are not comments.
    private func commands(of script: String) -> [String] {
        return script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }

    private func gitHubLinks(in text: String) -> Set<String> {
        let pattern = try! NSRegularExpression(pattern: "https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_-]+")
        let range = NSRange(text.startIndex..., in: text)
        return Set(pattern.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } })
    }

    // MARK: - Licence and notices

    /// LICENSE was the two-page summary that says of itself "not a substitute for the
    /// license", with no name in it. It is the notices and then the whole legal code.
    func testTheLicenceFileHasTheNoticesAndTheWholeLegalCode() throws {
        let licence = try text("LICENSE")
        XCTAssertTrue(licence.contains("Mos: Copyright © 2017–2026 Caldis and contributors."))
        XCTAssertTrue(licence.contains("Scrollio's changes: Copyright © 2026"))
        XCTAssertTrue(licence.contains("a modified version of Mos, https://github.com/Caldis/Mos"))
        XCTAssertTrue(licence.contains("https://creativecommons.org/licenses/by-nc/4.0/"))
        XCTAssertTrue(licence.contains("without\nwarranties of any kind"))

        XCTAssertTrue(licence.contains("Creative Commons Attribution-NonCommercial 4.0 International Public\nLicense"))
        for section in 1...8 {
            XCTAssertTrue(licence.contains("\nSection \(section) -- "), "section \(section) of the legal code is missing")
        }
        XCTAssertFalse(licence.contains("human-readable summary"), "the summary is not the licence")
        XCTAssertFalse(licence.contains("ShareAlike"), "that would be another licence")
    }

    /// Finder › Get Info showed Scrollio's author only. The original's notice has to be there.
    func testTheCopyrightLineOfTheAppNamesMosAndTheLicence() throws {
        let line = try XCTUnwrap(Bundle(for: AppDelegate.self).object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)
        XCTAssertTrue(line.contains("© 2017–2026 Caldis (Mos)"), line)
        XCTAssertTrue(line.contains("Changes © 2026"), line)
        XCTAssertTrue(line.contains("CC BY-NC 4.0"), line)
    }

    func testTheReadmeGivesBothCopyrightLines() throws {
        let readme = try text("README.md")
        XCTAssertTrue(readme.contains("Mos: Copyright © 2017–2026 Caldis and contributors."))
        XCTAssertTrue(readme.contains("Scrollio's changes: Copyright © 2026"))
        XCTAssertTrue(readme.contains("not affiliated with or endorsed by Apple or Logitech"))
    }

    // MARK: - Acknowledgements

    /// The file ships in the app (and `scripts/release.sh` puts it on the disk image): it
    /// is how a compiled copy gives Charts' licence and names what Scrollio is derived from.
    func testTheAppCarriesItsAcknowledgements() throws {
        let url = try XCTUnwrap(
            Bundle(for: AppDelegate.self).url(forResource: "Acknowledgements", withExtension: "txt"),
            "Acknowledgements.txt is not in the app bundle"
        )
        let shipped = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(shipped, try text("Scrollio/Acknowledgements.txt"))

        XCTAssertTrue(shipped.contains("Mos: Copyright © 2017–2026 Caldis and contributors."))
        XCTAssertTrue(shipped.contains("Mac Mouse Fix, by Noah Nübling"))
        XCTAssertTrue(shipped.contains("derived from it"))
        // Charts: the Apache licence in full, with its copyright line.
        XCTAssertTrue(shipped.contains("Copyright 2016-2019 Daniel Cohen Gindi & Philipp Jahoda"))
        XCTAssertTrue(shipped.contains("Apache License\n                           Version 2.0, January 2004"))
        XCTAssertTrue(shipped.contains("END OF TERMS AND CONDITIONS"))
    }

    /// The README's list and the app's are one list in two places.
    func testTheReadmeAndTheAppAcknowledgeTheSameProjects() throws {
        let readme = try text("README.md")
        let start = try XCTUnwrap(readme.range(of: "### Acknowledgements"))
        let end = try XCTUnwrap(readme.range(of: "\n---\n", range: start.upperBound..<readme.endIndex))
        let own = "https://github.com/Scorpio3310/scrollio"

        let inReadme = gitHubLinks(in: String(readme[start.upperBound..<end.lowerBound])).subtracting([own])
        let inApp = gitHubLinks(in: try text("Scrollio/Acknowledgements.txt")).subtracting([own])
        XCTAssertEqual(inReadme, inApp)

        for project in ["Caldis/Mos", "noah-nuebling/mac-mouse-fix", "jurplel/InstantSpaceSwitcher", "pwr-Solaar/Solaar",
                        "AprilNEA/OpenLogi", "PixlOne/logiops", "TomBadash/Mouser", "danielgindi/Charts"] {
            XCTAssertTrue(inReadme.contains("https://github.com/\(project)"), "\(project) is not acknowledged")
        }
    }

    // MARK: - DGCharts is for the debug build only

    /// The Release configuration leaves DGCharts out of the link, so a use of it that is
    /// not inside `#if DEBUG` would stop the release build. This says so earlier.
    func testEveryUseOfDGChartsIsInsideIfDebug() throws {
        let sources = Self.root.appendingPathComponent("Scrollio")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var users: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard let use = source.range(of: "import DGCharts") else { continue }
            users.append(url.lastPathComponent)
            let before = source[source.startIndex..<use.lowerBound]
            XCTAssertTrue(before.contains("\n#if DEBUG\n"), "\(url.lastPathComponent) imports DGCharts outside #if DEBUG")
            XCTAssertFalse(before.contains("#endif"), "\(url.lastPathComponent) imports DGCharts outside #if DEBUG")
            XCTAssertTrue(source.hasSuffix("#endif\n"), "\(url.lastPathComponent): the #if DEBUG must close at the end of the file")
        }
        XCTAssertEqual(users, ["MonitorViewController.swift"])

        let project = try text("Scrollio.xcodeproj/project.pbxproj")
        XCTAssertEqual(project.components(separatedBy: "EXCLUDED_SOURCE_FILE_NAMES = \"DGCharts*\";").count - 1, 1,
                       "the app's Release configuration, and only it, leaves DGCharts out")
    }

    // MARK: - The build scripts

    func testTheScriptsAreValidShell() throws {
        for script in ["scripts/install.sh", "scripts/release.sh", "scripts/qa/lint-logi-boundary.sh"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", script]      // -n: read and check, run nothing
            process.currentDirectoryURL = Self.root
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTAssertEqual(process.terminationStatus, 0, "\(script): \(output)")
        }
    }

    /// With a second .xcodeproj in the folder (a leftover of the project's older name),
    /// `xcodebuild` without `-project` stops: "contains 2 projects".
    func testEveryXcodebuildCallOfTheScriptsNamesTheProject() throws {
        for script in ["scripts/install.sh", "scripts/release.sh"] {
            let calls = commands(of: try text(script)).filter { $0.contains("xcodebuild ") }
            XCTAssertFalse(calls.isEmpty, "\(script) no longer builds?")
            for call in calls {
                XCTAssertTrue(call.contains("xcodebuild -project \"${APP_NAME}.xcodeproj\""), "\(script): \(call)")
            }
        }
    }

    /// Both scripts run under `set -o pipefail`. There, `tool | grep -q pattern` reads as
    /// "no match" exactly when there is one: grep leaves at the first match, the tool is
    /// ended by the closed pipe, and the pipeline counts as failed. The coverage check
    /// (`otool -l … | grep -q`) could never fire because of it.
    func testNoCheckOfTheScriptsPipesIntoGrepQ() throws {
        // One "|" (not "||"), then grep with its options; the options are what is captured.
        let pipeIntoGrep = try NSRegularExpression(pattern: "(?<!\\|)\\|\\s*grep((?:\\s+-[A-Za-z]+)*)")
        func pipesIntoQuietGrep(_ line: String) -> Bool {
            let range = NSRange(line.startIndex..., in: line)
            return pipeIntoGrep.matches(in: line, range: range).contains { match in
                guard let options = Range(match.range(at: 1), in: line) else { return false }
                return line[options].contains("q")
            }
        }
        XCTAssertTrue(pipesIntoQuietGrep("if otool -l \"$BINARY\" | grep -q -e \"__llvm_prf\"; then"))
        XCTAssertTrue(pipesIntoQuietGrep("printf '%s' \"$X\" |grep -Eq '^a'"))
        XCTAssertFalse(pipesIntoQuietGrep("if [ -e \"$A\" ] || grep -a -q -F \"DGCharts\" \"$BINARY\"; then"))
        XCTAssertFalse(pipesIntoQuietGrep("X=\"$(security find-identity | grep -F \"$ID\" || true)\""))

        for script in ["scripts/install.sh", "scripts/release.sh"] {
            let source = try text(script)
            XCTAssertTrue(source.contains("set -euo pipefail"))
            for line in commands(of: source) {
                XCTAssertFalse(pipesIntoQuietGrep(line), "\(script) pipes into grep -q: \(line)")
            }
        }
    }

    /// What the release script must keep doing; each line was a finding of the review
    /// before the first public build.
    func testTheReleaseScriptKeepsItsSafeguards() throws {
        let script = try text("scripts/release.sh")
        // The binary is stripped, and the script proves it.
        XCTAssertTrue(script.contains("\nDEPLOYMENT_POSTPROCESSING = YES\n"))
        XCTAssertTrue(script.contains("\nSTRIP_INSTALLED_PRODUCT = YES\n"))
        XCTAssertTrue(script.contains("grep -q ' OSO ' \"$SYMBOLS\""))
        XCTAssertTrue(script.contains("for folder in \"$HOME\" \"$REPO\" \"$DERIVED\""))
        // A release needs the tag v<version> on the commit; the script never makes or pushes one.
        XCTAssertTrue(script.contains("git tag --points-at HEAD --list 'v[0-9]*'"))
        XCTAssertTrue(script.contains("this commit has no version tag"))
        // (Its message says how to tag and push; that text is not a command.)
        let message = try XCTUnwrap(script.range(of: "cat >&2 <<'EOF'"))
        let messageEnd = try XCTUnwrap(script.range(of: "\nEOF\n", range: message.upperBound..<script.endIndex))
        let withoutMessage = String(script[..<message.lowerBound]) + String(script[messageEnd.upperBound...])
        let gitCommands = commands(of: withoutMessage).filter { $0.contains("git ") }
        XCTAssertEqual(gitCommands.count, 4, "rev-parse, status, rev-list and tag --points-at: \(gitCommands)")
        for command in gitCommands {
            let reads = ["git rev-parse --short HEAD", "git status --porcelain", "git rev-list --count HEAD", "git tag --points-at HEAD"]
            XCTAssertTrue(reads.contains { command.contains($0) },
                          "the release script must only read from git, never tag, fetch or push: \(command)")
        }
        // The image gets its name last, and whatever is unfinished goes when the script ends.
        XCTAssertTrue(script.contains("trap cleanup EXIT"))
        XCTAssertTrue(script.contains("cleanup() { rm -rf \"$WORK\"; }"))
        let lastCheck = try XCTUnwrap(script.range(of: "xcrun stapler validate \"$UNFINISHED_DMG\""))
        let rename = try XCTUnwrap(script.range(of: "mv \"$UNFINISHED_DMG\" \"$DMG\""))
        XCTAssertTrue(lastCheck.upperBound < rename.lowerBound)
        XCTAssertFalse(script.contains("-srcfolder \"$STAGE\" -ov -format UDZO \"$DMG\""), "the image must not be created under its final name")
        // The licences travel with the image.
        XCTAssertTrue(script.contains("cp \"$REPO/LICENSE\" \"$STAGE/LICENSE.txt\""))
        XCTAssertTrue(script.contains("\"$STAGE/Acknowledgements.txt\""))
        // A release never moves Package.resolved by itself.
        XCTAssertTrue(script.contains("-disableAutomaticPackageResolution"))
    }
}
