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

    private func data(_ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let url = Self.root.appendingPathComponent(path)
        return try XCTUnwrap(try? Data(contentsOf: url), "cannot read \(path)", file: file, line: line)
    }

    /// Runs a shell program with arguments ($1, $2 …); what it printed, errors included.
    private func bash(_ program: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", program, "bash"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return (process.terminationStatus, output)
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
        // Sparkle is part of the released app: its licence in full, with the licences of
        // the code it includes.
        XCTAssertTrue(shipped.contains("Copyright (c) 2006-2013 Andy Matuschak."))
        XCTAssertTrue(shipped.contains("Permission is hereby granted, free of charge, to any person obtaining a copy of"))
        XCTAssertTrue(shipped.contains("EXTERNAL LICENSES"))
        XCTAssertTrue(shipped.contains("Copyright (c) 2015 Orson Peters"))
    }

    /// The version in the acknowledgements is the one the project pins and the app embeds.
    func testTheAcknowledgedSparkleIsThePinnedOne() throws {
        let resolved = try text("Scrollio.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let pin = try XCTUnwrap(resolved.range(of: "\"identity\" : \"sparkle\""))
        let version = try XCTUnwrap(resolved.range(of: "\"version\" : \"", range: pin.upperBound..<resolved.endIndex))
        let end = try XCTUnwrap(resolved.range(of: "\"", range: version.upperBound..<resolved.endIndex))
        let pinned = String(resolved[version.upperBound..<end.lowerBound])
        XCTAssertTrue(try text("Scrollio/Acknowledgements.txt").contains("\nSparkle \(pinned)\n"), "Acknowledgements.txt does not name Sparkle \(pinned)")
        let project = try text("Scrollio.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("kind = exactVersion;\n\t\t\t\tversion = \(pinned);"), "the project does not pin Sparkle to exactly \(pinned)")
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
                        "AprilNEA/OpenLogi", "PixlOne/logiops", "TomBadash/Mouser", "danielgindi/Charts",
                        "sparkle-project/Sparkle"] {
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
        for script in ["scripts/install.sh", "scripts/release.sh", "scripts/release-lib.sh", "scripts/update-key.sh",
                       "scripts/dmg/preview.sh", "scripts/qa/lint-logi-boundary.sh"] {
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
        for script in ["scripts/install.sh", "scripts/release.sh", "scripts/update-key.sh"] {
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

        // release-lib.sh is sourced by release.sh and runs under its settings.
        for script in ["scripts/install.sh", "scripts/release.sh", "scripts/release-lib.sh", "scripts/update-key.sh",
                       "scripts/dmg/preview.sh"] {
            let source = try text(script)
            if script != "scripts/release-lib.sh" {
                XCTAssertTrue(source.contains("set -euo pipefail"), script)
            }
            for line in commands(of: source) {
                XCTAssertFalse(pipesIntoQuietGrep(line), "\(script) pipes into grep -q: \(line)")
            }
        }
    }

    /// The build number is the number of commits, and an installed copy takes a release
    /// only when that number is larger than its own.
    func testTheReleaseScriptRefusesABuildNumberThatDidNotGrow() throws {
        let script = try text("scripts/release.sh")
        func position(_ needle: String, file: StaticString = #filePath, line: UInt = #line) throws -> String.Index {
            return try XCTUnwrap(script.range(of: needle), "scripts/release.sh no longer has: \(needle)", file: file, line: line).lowerBound
        }
        // A shallow clone counts too few commits.
        let shallow = try position("[ \"$(git rev-parse --is-shallow-repository)\" = \"false\" ]")
        let count = try position("COUNT=\"$(git rev-list --count HEAD)\"")
        // Every other release's commit must come before this one.
        let older = try position("[ \"$OLDER\" -lt \"$COUNT\" ]")
        let build = try position("SCROLLIO_UPDATE_FEED=\"$UPDATE_FEED\"")
        XCTAssertTrue(shallow < count && count < older && older < build)
        XCTAssertTrue(script.contains("if grep -qxF -- \"$tag\" <<< \"$TAGS\"; then continue; fi"), "the tags on this commit are not \"earlier releases\"")
        // The appcast carries the number the built app says, and that is the commit count.
        XCTAssertTrue(script.contains("[ \"$BUILT_BUILD\" = \"$COUNT\" ]"))
        XCTAssertTrue(script.contains("write_appcast \"$WORK/appcast.xml\" \"$VERSION\" \"$BUILT_BUILD\""))
    }

    /// The functions of scripts/release-lib.sh that only write text, run for real: the
    /// changelog part of a version, the three-part macOS version, and the appcast.
    func testTheReleaseLibraryWritesTheChangelogPartAndTheAppcast() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScrollioReleaseLib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let changelog = "# Changelog\n\nIntro.\n\n## 1.10\n\n- ten\n\n## 1.1 (2026-11-12)\n\n\n- one, with ]]> in it\n- and <b>markup</b> & more\n\n\n## 1.0.0\n\nFirst.\n"
        try changelog.write(to: folder.appendingPathComponent("CHANGELOG.md"), atomically: true, encoding: .utf8)
        let program = """
        set -euo pipefail
        fail() { echo "FAIL: $*" >&2; exit 1; }
        REPO="$1"; LOG="$1/log.txt"; APP_NAME="Scrollio"; RELEASES_URL="https://github.com/Scorpio3310/scrollio/releases"
        . "$2"
        echo "three_part: $(three_part 14.0) $(three_part 15) $(three_part 14.2.1)"
        echo "--- 1.1"; changelog_section 1.1
        echo "--- 1.10"; changelog_section 1.10
        echo "--- 1.0.0"; changelog_section 1.0.0
        echo "--- 9.9"; changelog_section 9.9
        echo "--- end"
        changelog_section 1.1 > "$1/notes.md"
        : > "$1/empty.md"
        write_appcast "$1/appcast.xml" 1.1 1650 14.0.0 "c2lnbmF0dXJl+/==" 5590100 "$1/notes.md"
        write_appcast "$1/appcast-plain.xml" 1.0.1 1700 14.0.0 "c2ln" 42 "$1/empty.md"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", program, "bash", folder.path, Self.root.appendingPathComponent("scripts/release-lib.sh").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)

        XCTAssertTrue(output.contains("three_part: 14.0.0 15.0.0 14.2.1\n"), output)
        // A version's part: its own lines only ("1.1" is not "1.10"), without the empty lines around them.
        XCTAssertTrue(output.contains("--- 1.1\n- one, with ]]> in it\n- and <b>markup</b> & more\n--- 1.10\n- ten\n--- 1.0.0\nFirst.\n--- 9.9\n--- end\n"), output)

        // The appcast is XML a parser reads back, with every value where Sparkle looks for it.
        let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
        let document = try XMLDocument(contentsOf: folder.appendingPathComponent("appcast.xml"), options: [])
        func first(_ path: String) throws -> XMLNode { return try XCTUnwrap(try document.nodes(forXPath: path).first, path) }
        XCTAssertEqual(try first("/rss/channel/item/title").stringValue, "Scrollio 1.1")
        XCTAssertEqual(try first("/rss/channel/item/link").stringValue, "https://github.com/Scorpio3310/scrollio/releases/tag/v1.1")
        let item = try XCTUnwrap(try first("/rss/channel/item") as? XMLElement)
        func value(_ name: String) throws -> String? {
            return try XCTUnwrap(item.elements(forLocalName: name, uri: sparkle).first, name).stringValue
        }
        XCTAssertEqual(try value("version"), "1650")
        XCTAssertEqual(try value("shortVersionString"), "1.1")
        XCTAssertEqual(try value("minimumSystemVersion"), "14.0.0")
        XCTAssertEqual(try value("fullReleaseNotesLink"), "https://github.com/Scorpio3310/scrollio/releases")
        let notes = try XCTUnwrap(item.elements(forName: "description").first)
        XCTAssertEqual(notes.attribute(forLocalName: "format", uri: sparkle)?.stringValue, "markdown")
        XCTAssertEqual(notes.stringValue, "- one, with ]]> in it\n- and <b>markup</b> & more\n", "the notes arrive as they were written")
        let enclosure = try XCTUnwrap(item.elements(forName: "enclosure").first)
        XCTAssertEqual(enclosure.attribute(forName: "url")?.stringValue, "https://github.com/Scorpio3310/scrollio/releases/download/v1.1/Scrollio-1.1.dmg")
        XCTAssertEqual(enclosure.attribute(forLocalName: "edSignature", uri: sparkle)?.stringValue, "c2lnbmF0dXJl+/==")
        XCTAssertEqual(enclosure.attribute(forName: "length")?.stringValue, "5590100")
        XCTAssertEqual(try document.nodes(forXPath: "/rss/channel/item").count, 1)
        XCTAssertNotNil(try first("/rss/channel/item/pubDate").stringValue)

        // Without notes the item has no description at all.
        let plain = try XMLDocument(contentsOf: folder.appendingPathComponent("appcast-plain.xml"), options: [])
        XCTAssertTrue(try plain.nodes(forXPath: "/rss/channel/item/description").isEmpty)
        XCTAssertEqual(try plain.nodes(forXPath: "/rss/channel/item/enclosure/@url").first?.stringValue,
                       "https://github.com/Scorpio3310/scrollio/releases/download/v1.0.1/Scrollio-1.0.1.dmg")
    }

    /// The key helper never writes the private key into the repository.
    func testTheKeyHelperKeepsTheKeyFileOutOfTheRepository() throws {
        let script = try text("scripts/update-key.sh")
        let callerDir = try XCTUnwrap(script.range(of: "CALLER_DIR=\"$PWD\""))
        let cd = try XCTUnwrap(script.range(of: "cd \"$(dirname \"$0\")/..\""))
        XCTAssertTrue(callerDir.lowerBound < cd.lowerBound, "the caller's folder is remembered before the script changes folder")
        XCTAssertTrue(script.contains("is inside the repository: keep the private key out of it"))
        XCTAssertTrue(script.contains("FILE=\"$(key_file \"$2\")\""))
        XCTAssertEqual(script.components(separatedBy: "FILE=\"$(key_file \"$2\")\"").count - 1, 2, "export and import")
        XCTAssertFalse(commands(of: script).contains { $0.contains("generate_keys") && ($0.contains("-x \"$2\"") || $0.contains("-f \"$2\"")) })
        XCTAssertTrue(script.contains("umask 077"))
    }

    /// What makes a release an update, and what keeps a wrong one from going out.
    func testTheReleaseScriptMakesTheReleaseAnUpdate() throws {
        let script = try text("scripts/release.sh")
        let library = try text("scripts/release-lib.sh")
        XCTAssertTrue(script.contains(". \"$REPO/scripts/release-lib.sh\""))
        func position(_ needle: String, file: StaticString = #filePath, line: UInt = #line) throws -> String.Index {
            return try XCTUnwrap(script.range(of: needle), "scripts/release.sh no longer has: \(needle)", file: file, line: line).lowerBound
        }
        // The key in the keychain is the app's and can sign, before the long build.
        let keyCheck = try position("[ \"$KEYCHAIN_PUBLIC_KEY\" = \"$APP_PUBLIC_KEY\" ]")
        let probe = try position("--verify \"$PROBE\" \"$PROBE_SIGNATURE\"")
        let build = try position("SCROLLIO_UPDATE_FEED=\"$UPDATE_FEED\"")
        XCTAssertTrue(keyCheck < probe && probe < build)
        // Only what has the shape of a public key counts as one (the tool prints its error on standard output).
        XCTAssertTrue(script.contains("grep -Eq '^[A-Za-z0-9+/]{43}=$' <<< \"$KEYCHAIN_PUBLIC_KEY\" || KEYCHAIN_PUBLIC_KEY=\"\""))
        // Sparkle's helpers are signed before anything looks at a signature, and then every program is looked at.
        let helpers = try position("sign_sparkle_helpers \"$BUILT\"")
        let firstLook = try position("SIGNATURE=\"$(codesign -dvv \"$BUILT\" 2>&1)\"")
        let programs = try position("check_programs \"$BUILT\" \"Developer ID Application\" \"$TEAM\"")
        XCTAssertTrue(build < helpers && helpers < firstLook && firstLook < programs)
        XCTAssertTrue(script.contains("[ \"$PROGRAMS\" -ge 6 ]"))
        // The built app asks the right place and trusts the right key.
        XCTAssertTrue(script.contains("[ \"$BUILT_FEED\" = \"$UPDATE_FEED\" ]"))
        XCTAssertTrue(script.contains("[ \"$BUILT_KEY\" = \"$KEYCHAIN_PUBLIC_KEY\" ]"))
        XCTAssertTrue(script.contains("[ \"$BUILT_VERIFIES\" = \"true\" ]"))
        // The image is signed as an update after it was stapled (stapling changes it), the
        // signature is verified, and the appcast gets its name with the image, last.
        let stapled = try position("xcrun stapler validate \"$UNFINISHED_DMG\"")
        let signed = try position("sign_update\" --account \"$KEY_ACCOUNT\" -p \"$UNFINISHED_DMG\"")
        let verified = try position("sign_update\" --account \"$KEY_ACCOUNT\" --verify \"$UNFINISHED_DMG\" \"$ED_SIGNATURE\"")
        let imageNamed = try position("mv \"$UNFINISHED_DMG\" \"$DMG\"")
        let appcastNamed = try position("mv \"$WORK/appcast.xml\" \"$APPCAST\"")
        XCTAssertTrue(stapled < signed && signed < verified && verified < imageNamed && imageNamed < appcastNamed)
        XCTAssertTrue(script.contains("APPCAST=\"$DERIVED/appcast.xml\""), "the installed copies ask for a file of exactly this name")
        // The library: the helpers by name, never --deep, and the requirement the permission hangs on.
        for helper in ["XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Autoupdate", "Updater.app"] {
            XCTAssertTrue(library.contains("\"$code/\(helper)\""), helper)
        }
        XCTAssertTrue(library.contains("sign_one --preserve-metadata=entitlements \"$code/XPCServices/Downloader.xpc\""))
        XCTAssertFalse(commands(of: library).contains { $0.contains("codesign") && $0.contains("--deep") })
        XCTAssertTrue(library.contains("[ -n \"$after\" ] && [ \"$after\" = \"$before\" ]"))
        // The app is signed again with the requirement the build wrote: for a Developer ID
        // codesign's own default reads differently (found when the script first ran with one).
        XCTAssertTrue(library.contains("sign_one --preserve-metadata=entitlements,requirements \"$app\""))
        XCTAssertTrue(library.contains("--options runtime --timestamp"))
        // The release script only reads the key's public half: it never makes, exports or imports a key.
        let keyToolRuns = commands(of: script + "\n" + library).filter { $0.contains("generate_keys\" --account") }
        XCTAssertEqual(keyToolRuns.count, 1, "\(keyToolRuns)")
        XCTAssertTrue(keyToolRuns.allSatisfy { $0.contains("generate_keys\" --account \"$KEY_ACCOUNT\" -p ") }, "\(keyToolRuns)")
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
        XCTAssertEqual(gitCommands.count, 7, "rev-parse (twice), status, rev-list (twice), tag --points-at and tag --list: \(gitCommands)")
        for command in gitCommands {
            let reads = ["git rev-parse --short HEAD", "git status --porcelain", "git rev-list --count HEAD", "git tag --points-at HEAD",
                         "git rev-parse --is-shallow-repository", "git rev-list --count \"$tag\"", "git tag --list 'v[0-9]*'"]
            XCTAssertTrue(reads.contains { command.contains($0) },
                          "the release script must only read from git, never tag, fetch or push: \(command)")
        }
        // The image gets its name last, and whatever is unfinished goes when the script ends.
        XCTAssertTrue(script.contains("trap cleanup EXIT"))
        XCTAssertTrue(script.contains("cleanup() { rm -rf \"$WORK\"; }"))
        let lastCheck = try XCTUnwrap(script.range(of: "xcrun stapler validate \"$UNFINISHED_DMG\""))
        let rename = try XCTUnwrap(script.range(of: "mv \"$UNFINISHED_DMG\" \"$DMG\""))
        XCTAssertTrue(lastCheck.upperBound < rename.lowerBound)
        // The image is made in one place, by the library's function, and not under its final name.
        XCTAssertTrue(script.contains("\nmake_disk_image \"$STAGE\" \"$UNFINISHED_DMG\"\n"))
        XCTAssertEqual(commands(of: script).filter { $0.contains("make_disk_image") || $0.contains("hdiutil create") }.count, 1,
                       "the image must not be created under its final name")
        // The licences travel with the image (the library fills it; a test below runs that).
        XCTAssertTrue(script.contains("\nstage_disk_image \"$STAPLED\" \"$STAGE\"\n"))
        let library = try text("scripts/release-lib.sh")
        XCTAssertTrue(library.contains("cp \"$REPO/LICENSE\" \"$stage/LICENSE.txt\""))
        XCTAssertTrue(library.contains("\"$stage/Acknowledgements.txt\""))
        // A release never moves Package.resolved by itself.
        XCTAssertTrue(script.contains("-disableAutomaticPackageResolution"))
    }

    // MARK: - The disk image's window

    /// What a person sees on the image. Its two other items are hidden: the layout
    /// (".DS_Store") and the folder of the window's picture (".background").
    private static let imageItems = ["Scrollio.app", "Applications", "LICENSE.txt", "Acknowledgements.txt"]
    /// The window's content, which is the picture's size in points, and the title bar
    /// stored with it (its height on macOS 14 and 15; higher on later ones, where the
    /// picture's lowest points are then not seen).
    private static let windowContent = (width: 660, height: 420)
    private static let titleBarHeight = 28

    /// `stage_disk_image` of scripts/release-lib.sh, run for real with a stand-in for the
    /// built app: the folder holds exactly what the image should hold.
    func testTheDiskImageIsFilledWithTheAppTheLinkTheTextsAndItsWindow() throws {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("ScrollioDiskImage-\(UUID().uuidString)")
        let resources = folder.appendingPathComponent("built/Scrollio.app/Contents/Resources")
        try files.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        try "what Scrollio owes\n".write(to: resources.appendingPathComponent("Acknowledgements.txt"), atomically: true, encoding: .utf8)
        let program = """
        set -euo pipefail
        fail() { echo "FAIL: $*" >&2; exit 1; }
        REPO="$1"; LOG="$2/log.txt"; APP_NAME="Scrollio"
        . "$3"
        stage_disk_image "$2/built/Scrollio.app" "$2/image"
        """
        let library = Self.root.appendingPathComponent("scripts/release-lib.sh").path
        let first = try bash(program, [Self.root.path, folder.path, library])
        XCTAssertEqual(first.status, 0, first.output)

        let image = folder.appendingPathComponent("image")
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: image.path)), Set(Self.imageItems + [".DS_Store", ".background"]))
        XCTAssertEqual(try files.contentsOfDirectory(atPath: image.appendingPathComponent(".background").path), ["background.tiff"])
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: image.appendingPathComponent("Applications").path), "/Applications")
        XCTAssertEqual(try Data(contentsOf: image.appendingPathComponent("LICENSE.txt")), try data("LICENSE"))
        XCTAssertEqual(try String(contentsOf: image.appendingPathComponent("Acknowledgements.txt"), encoding: .utf8), "what Scrollio owes\n")
        XCTAssertTrue(files.fileExists(atPath: image.appendingPathComponent("Scrollio.app/Contents/Resources/Acknowledgements.txt").path))
        XCTAssertEqual(try Data(contentsOf: image.appendingPathComponent(".DS_Store")), try data("scripts/dmg/DS_Store"))
        XCTAssertEqual(try Data(contentsOf: image.appendingPathComponent(".background/background.tiff")), try data("scripts/dmg/background.tiff"))

        // A folder that holds something already is refused: all of it would be on the image.
        let second = try bash(program, [Self.root.path, folder.path, library])
        XCTAssertNotEqual(second.status, 0)
        XCTAssertTrue(second.output.contains("FAIL: the folder for the disk image is not empty"), second.output)

        // Without the picture, and then without the layout, the run ends with a sentence that names the file.
        let bare = folder.appendingPathComponent("repository")
        try files.createDirectory(at: bare.appendingPathComponent("scripts/dmg"), withIntermediateDirectories: true)
        try files.copyItem(at: Self.root.appendingPathComponent("LICENSE"), to: bare.appendingPathComponent("LICENSE"))
        try files.removeItem(at: image)
        let noPicture = try bash(program, [bare.path, folder.path, library])
        XCTAssertNotEqual(noPicture.status, 0)
        XCTAssertTrue(noPicture.output.contains("FAIL: the picture of the disk image's window is missing: scripts/dmg/background.tiff"), noPicture.output)
        try files.copyItem(at: Self.root.appendingPathComponent("scripts/dmg/background.tiff"), to: bare.appendingPathComponent("scripts/dmg/background.tiff"))
        let noLayout = try bash(program, [bare.path, folder.path, library])
        XCTAssertNotEqual(noLayout.status, 0)
        XCTAssertTrue(noLayout.output.contains("FAIL: the layout of the disk image's window is missing: scripts/dmg/DS_Store"), noLayout.output)
        XCTAssertFalse(files.fileExists(atPath: image.path), "nothing is filled before both are there")
    }

    /// The layout (scripts/dmg/DS_Store, on the image Finder's ".DS_Store"), read back by a
    /// reader of this file's own: the window, the icon view and the icons' places are the
    /// numbers the picture is drawn for, and it names exactly the items the image holds.
    func testTheLayoutOfTheDiskImageWindowIsWhatThePictureIsDrawnFor() throws {
        let file = try data("scripts/dmg/DS_Store")
        let records = try DiskImageLayout.records(in: file)
        func plist(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
            let record = try XCTUnwrap(records.first { $0.name == "." && $0.id == id }, "no \(id)", file: file, line: line)
            XCTAssertEqual(record.type, "blob", file: file, line: line)
            return try XCTUnwrap(try PropertyListSerialization.propertyList(from: record.value, format: nil) as? [String: Any], file: file, line: line)
        }

        // The folder's own three records and one place per item, in the tree's order
        // (by name without regard to case, then by id): nothing else, and no item without a place.
        XCTAssertEqual(records.map { "\($0.name) \($0.id)" },
                       [". bwsp", ". icvp", ". vSrn"] + Self.imageItems.sorted { $0.lowercased() < $1.lowercased() }.map { "\($0) Iloc" })

        // The window: as wide and as high as the picture below a 28 pt title bar; no toolbar, sidebar or bars.
        let window = try plist("bwsp")
        let bounds = try XCTUnwrap(window["WindowBounds"] as? String)
        let numbers = bounds.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 4, bounds)
        XCTAssertEqual(Array(numbers.suffix(2)), [Self.windowContent.width, Self.windowContent.height + Self.titleBarHeight], bounds)
        for bar in ["ShowToolbar", "ShowSidebar", "ContainerShowSidebar", "ShowStatusBar", "ShowPathbar", "ShowTabView"] {
            XCTAssertEqual(window[bar] as? Bool, false, bar)
        }

        // The icon view: 128 pt icons that stay where they are put, 13 pt names below them, a picture behind.
        let view = try plist("icvp")
        XCTAssertEqual(view["iconSize"] as? Double, 128)
        XCTAssertEqual(view["textSize"] as? Double, 13)
        XCTAssertEqual(view["arrangeBy"] as? String, "none")
        XCTAssertEqual(view["labelOnBottom"] as? Bool, true)
        XCTAssertEqual(view["showItemInfo"] as? Bool, false)
        XCTAssertEqual(view["backgroundType"] as? Int, 2)

        // Where the icons' centres are, from the top left corner of the window's content.
        var places: [String: (x: Int, y: Int)] = [:]
        for record in records where record.id == "Iloc" {
            let bytes = [UInt8](record.value)
            XCTAssertEqual(bytes.count, 16, record.name)
            func number(_ at: Int) -> Int { return bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
            places[record.name] = (number(0), number(4))
        }
        let app = try XCTUnwrap(places["Scrollio.app"])
        let applications = try XCTUnwrap(places["Applications"])
        XCTAssertTrue(app == (180, 184), "\(app)")
        XCTAssertTrue(applications == (480, 184), "\(applications)")
        // The two text files begin below what the window shows, so two icons are seen.
        for name in ["LICENSE.txt", "Acknowledgements.txt"] {
            let place = try XCTUnwrap(places[name])
            XCTAssertGreaterThan(place.y - 64, Self.windowContent.height, name)
            XCTAssertTrue((64...(Self.windowContent.width - 64)).contains(place.x), name)
        }

        // The script that writes the file is run by hand: it says the same numbers, so a
        // change there does not pass without a new file.
        let writer = try text("scripts/dmg/write-layout.swift")
        for line in ["let contentWidth = 660\n", "let contentHeight = 420\n", "let titleBarHeight = 28\n", "let iconSize = 128.0\n",
                     "let textSize = 13.0\n", "    (\"Scrollio.app\", 180, 184),\n", "    (\"Applications\", 480, 184),\n",
                     "    (\"LICENSE.txt\", \(try XCTUnwrap(places["LICENSE.txt"]).x), \(try XCTUnwrap(places["LICENSE.txt"]).y)),\n",
                     "    (\"Acknowledgements.txt\", \(try XCTUnwrap(places["Acknowledgements.txt"]).x), \(try XCTUnwrap(places["Acknowledgements.txt"]).y)),\n"] {
            XCTAssertTrue(writer.contains(line), "scripts/dmg/write-layout.swift no longer has: \(line)")
        }

        // The picture is found by an alias: the volume's name and the path on it, as
        // `stage_disk_image` and `make_disk_image` make them.
        let alias = try DiskImageLayout.Alias(try XCTUnwrap(view["backgroundImageAlias"] as? Data))
        XCTAssertEqual(alias.volume, "Scrollio")
        XCTAssertEqual(alias.file, "background.tiff")
        XCTAssertEqual(alias.fileSystem, "H+")
        XCTAssertEqual(alias.text(15, utf16: true), "Scrollio")
        XCTAssertEqual(alias.text(14, utf16: true), "background.tiff")
        XCTAssertEqual(alias.text(18), "/.background/background.tiff")
        XCTAssertEqual(alias.text(19), "/Volumes/Scrollio")
        let library = try text("scripts/release-lib.sh")
        XCTAssertTrue(library.contains("hdiutil create -volname \"$APP_NAME\" -srcfolder \"$1\" -fs HFS+ "))
        XCTAssertTrue(library.contains("cp \"$REPO/$DMG_PICTURE\" \"$stage/.background/background.tiff\""))
        XCTAssertTrue(library.contains("cp \"$REPO/$DMG_LAYOUT\" \"$stage/.DS_Store\""))
        for script in ["scripts/release.sh", "scripts/dmg/preview.sh"] {
            XCTAssertTrue(try text(script).contains("\nAPP_NAME=\"Scrollio\"\n"), script)
        }
        // Every release's image is a new volume: an alias with one image's dates and file
        // numbers would be looked up by them first. Zero means "not known".
        XCTAssertEqual(alias.numbers, [0, 0, 0, 0], "the volume's date, the folder's number, the file's number and date")
        // Nothing of the Mac it was made on: no alias of an image file (piece 20), no bookmark
        // (it would be a record of its own, "pBBk"), no path of a home folder.
        XCTAssertEqual(alias.pieces.keys.sorted(), [0, 1, 2, 14, 15, 18, 19])
        for needle in ["/Users/", NSHomeDirectory()] {
            XCTAssertNil(file.range(of: Data(needle.utf8)), "the layout contains \(needle)")
            XCTAssertNil(file.range(of: needle.data(using: .utf16BigEndian)!), "the layout contains \(needle)")
        }
    }

    /// One TIFF with the picture twice: for a plain display and for a Retina display.
    func testThePictureOfTheDiskImageWindowHasBothResolutions() throws {
        let pictures = NSBitmapImageRep.imageReps(with: try data("scripts/dmg/background.tiff")).compactMap { $0 as? NSBitmapImageRep }
        XCTAssertEqual(pictures.map { [$0.pixelsWide, $0.pixelsHigh] }.sorted { $0[0] < $1[0] },
                       [[Self.windowContent.width, Self.windowContent.height], [Self.windowContent.width * 2, Self.windowContent.height * 2]])
        for picture in pictures {
            XCTAssertEqual(picture.size, NSSize(width: Self.windowContent.width, height: Self.windowContent.height), "both are the window's size in points")
        }
    }

    /// The window costs a release nothing new: no scripted Finder, and a missing picture
    /// stops the run before the build, not after Apple accepted the app.
    func testTheReleaseScriptGivesTheImageItsWindow() throws {
        let script = try text("scripts/release.sh")
        let library = try text("scripts/release-lib.sh")
        let preview = try text("scripts/dmg/preview.sh")
        func position(_ needle: String, file: StaticString = #filePath, line: UInt = #line) throws -> String.Index {
            return try XCTUnwrap(script.range(of: needle), "scripts/release.sh no longer has: \(needle)", file: file, line: line).lowerBound
        }
        let required = try position("\nrequire_disk_image_window\n")
        let build = try position("SCROLLIO_UPDATE_FEED=\"$UPDATE_FEED\"")
        // The app gets Apple's ticket, then the folder is filled with that copy, packed and signed.
        let stapled = try position("staple \"$STAPLED\"")
        let filled = try position("\nstage_disk_image \"$STAPLED\" \"$STAGE\"\n")
        let packed = try position("\nmake_disk_image \"$STAGE\" \"$UNFINISHED_DMG\"\n")
        let signed = try position("codesign --sign \"$IDENTITY\" --timestamp \"$UNFINISHED_DMG\"")
        XCTAssertTrue(required < build && build < stapled && stapled < filled && filled < packed && packed < signed)
        // Gatekeeper is asked about the copy that is on the image.
        XCTAssertTrue(script.contains("spctl --assess --type execute -vv \"$STAGE/${APP_NAME}.app\""))
        XCTAssertTrue(library.contains("stage_disk_image() {\n    local app=\"$1\" stage=\"$2\"\n    require_disk_image_window\n"))
        XCTAssertTrue(script.contains("echo \"release: opened, the image is a window: "))

        // The sample image is filled and packed by the same two functions.
        XCTAssertTrue(preview.contains(". \"$REPO/scripts/release-lib.sh\""))
        XCTAssertTrue(preview.contains("\nstage_disk_image \"$APP\" \"$OUT/image\"\nmake_disk_image \"$OUT/image\" \"$IMAGE\"\n"))
        // It is not a release: nothing is built, signed, notarized, read from the keychain or opened.
        for line in commands(of: preview) {
            for tool in ["xcodebuild", "codesign", "notarytool", "stapler", "spctl", "security ", "sign_update", "generate_keys", "hdiutil attach"] {
                XCTAssertFalse(line.contains(tool), "scripts/dmg/preview.sh: \(line)")
            }
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).hasPrefix("open "), "scripts/dmg/preview.sh: \(line)")
        }
        // No script that makes an image scripts Finder or another app: that would ask for a permission.
        for line in commands(of: script + "\n" + library + "\n" + preview) {
            for scripting in ["osascript", "tell application", "System Events"] {
                XCTAssertFalse(line.contains(scripting), line)
            }
        }
    }
}

// MARK: - A reader of the layout file

/// Reads the records of a ".DS_Store" file, and the alias inside one. Written for the
/// tests above, apart from scripts/dmg/write-layout.swift, which writes the file: a
/// mistake in one is not repeated in the other. It reads the file as Finder writes it too.
private enum DiskImageLayout {

    struct Unreadable: Error, CustomStringConvertible {
        let description: String
    }

    struct Record {
        /// The item's name; "." is the folder itself.
        let name: String
        let id: String
        let type: String
        /// The value without its length: a property list's or a place's bytes.
        let value: Data
    }

    /// Big-endian numbers and texts, read one after the other.
    private struct Bytes {
        let all: [UInt8]
        var at: Int

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, at + count <= all.count else { throw Unreadable(description: "the file ends at byte \(at)") }
            defer { at += count }
            return Array(all[at..<(at + count)])
        }
        mutating func number(_ count: Int = 4) throws -> Int {
            return try take(count).reduce(0) { $0 << 8 | Int($1) }
        }
        mutating func ascii(_ count: Int) throws -> String {
            return String(decoding: try take(count), as: UTF8.self)
        }
        mutating func utf16(_ units: Int) throws -> String {
            guard let text = String(data: Data(try take(units * 2)), encoding: .utf16BigEndian) else {
                throw Unreadable(description: "a name that is not UTF-16 at byte \(at)")
            }
            return text
        }
    }

    /// Every record, in the order of the tree.
    static func records(in file: Data) throws -> [Record] {
        let all = [UInt8](file)
        // The header. Offsets in the file count from after its first four bytes.
        var header = Bytes(all: all, at: 0)
        guard try header.number() == 1, try header.ascii(4) == "Bud1" else { throw Unreadable(description: "not a Bud1 store") }
        let listOffset = try header.number()
        _ = try header.number()
        guard try header.number() == listOffset else { throw Unreadable(description: "the two offsets of the block list differ") }

        // The allocator's list: where each block is (the offset, with the power of two of
        // its size in the low five bits), then the named blocks.
        var list = Bytes(all: all, at: 4 + listOffset)
        let count = try list.number()
        _ = try list.number()
        guard count <= 256 else { throw Unreadable(description: "more blocks than one list holds") }
        let addresses = try (0..<count).map { _ in try list.number() }
        list.at = 4 + listOffset + 8 + 256 * 4
        var head: Int?
        for _ in 0..<(try list.number()) {
            let name = try list.ascii(try list.number(1))
            let block = try list.number()
            if name == "DSDB" { head = block }
        }
        func block(_ number: Int) throws -> Bytes {
            guard addresses.indices.contains(number) else { throw Unreadable(description: "no block \(number)") }
            return Bytes(all: all, at: 4 + (addresses[number] & ~0x1F))
        }

        // The tree's head: its root node and how many records it holds.
        guard let head else { throw Unreadable(description: "no block named DSDB") }
        var tree = try block(head)
        let root = try tree.number()
        _ = try tree.number()
        let recordCount = try tree.number()

        var records: [Record] = []
        func read(node number: Int) throws {
            var node = try block(number)
            let last = try node.number()            // 0 in a leaf, else the child after the last record
            for _ in 0..<(try node.number()) {
                if last != 0 { try read(node: try node.number()) }
                let name = try node.utf16(try node.number())
                let id = try node.ascii(4)
                let type = try node.ascii(4)
                let value: [UInt8]
                switch type {
                case "blob": value = try node.take(try node.number())
                case "ustr": value = try node.take(try node.number() * 2)
                case "bool": value = try node.take(1)
                case "long", "shor", "type": value = try node.take(4)
                case "comp", "dutc": value = try node.take(8)
                default: throw Unreadable(description: "a record of type \(type)")
                }
                records.append(Record(name: name, id: id, type: type, value: Data(value)))
            }
            if last != 0 { try read(node: last) }
        }
        try read(node: root)
        guard records.count == recordCount else { throw Unreadable(description: "the tree says \(recordCount) records and holds \(records.count)") }
        return records
    }

    /// An alias record of version 2: the fixed part, then numbered pieces.
    struct Alias {
        let volume: String
        let file: String
        let fileSystem: String
        /// The volume's creation date, the folder's file number, the file's number and its creation date.
        let numbers: [Int]
        let pieces: [Int: Data]

        init(_ data: Data) throws {
            var bytes = Bytes(all: [UInt8](data), at: 4)
            guard try bytes.number(2) == data.count, try bytes.number(2) == 2 else { throw Unreadable(description: "not an alias record of version 2") }
            func pascal(_ width: Int) throws -> String {
                let field = try bytes.take(width)
                return String(decoding: field[1..<(1 + Int(field[0]))], as: UTF8.self)
            }
            _ = try bytes.number(2)                 // a file or a folder
            volume = try pascal(28)
            let volumeDate = try bytes.number()
            fileSystem = try bytes.ascii(2)
            _ = try bytes.number(2)                 // the kind of disk
            let folderNumber = try bytes.number()
            file = try pascal(64)
            numbers = [volumeDate, folderNumber, try bytes.number(), try bytes.number()]
            _ = try bytes.take(28)                  // creator, type, levels, volume attributes, file system id, reserved
            var pieces: [Int: Data] = [:]
            while true {
                let number = try bytes.number(2)
                let length = try bytes.number(2)
                if number == 0xFFFF { break }
                pieces[number] = Data(try bytes.take(length))
                if length % 2 == 1 { _ = try bytes.take(1) }
            }
            guard bytes.at == data.count else { throw Unreadable(description: "bytes after the alias's end") }
            self.pieces = pieces
        }

        /// A piece as text; the UTF-16 ones begin with their length.
        func text(_ piece: Int, utf16: Bool = false) -> String? {
            guard let data = pieces[piece] else { return nil }
            return utf16 ? String(data: data.dropFirst(2), encoding: .utf16BigEndian) : String(data: data, encoding: .utf8)
        }
    }
}
