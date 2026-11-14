//
//  PreferencesDisclosureSectionTests.swift
//  ScrollioTests
//
//  The section whose title folds what is under it (PreferencesDisclosureSection): an
//  ordinary titled section while it cannot fold, folded when it can, opened and folded by a
//  click, Space and VoiceOver, the chevron that turns (at once with Reduce Motion), the
//  title that never moves, and what opens can be used. Nothing is shown on screen.
//

import XCTest
@testable import Scrollio_Debug

final class PreferencesDisclosureSectionTests: XCTestCase {

    private typealias Form = PreferencesGroupedForm

    private let paneWidth: CGFloat = 520
    private var boxWidth: CGFloat { Form.boxWidth(paneWidth: paneWidth) }

    private var toggle: NSSwitch!
    private var window: NSWindow?

    override func tearDown() {
        window?.close()
        window = nil
        toggle = nil
        super.tearDown()
    }

    /// A section titled "Directions" over a box with one switch row.
    private func makeSection(collapsible: Bool, reducedMotion: Bool = true) -> PreferencesDisclosureSection {
        let row = PreferencesSwitchRow(title: "Invert", target: nil, action: nil)
        toggle = row.toggle
        let box = PreferencesGroupBox(width: boxWidth, rows: [row])
        let section = PreferencesDisclosureSection(title: "Directions", body: box)
        section.prefersReducedMotion = { reducedMotion }
        section.isCollapsible = collapsible
        return section
    }

    /// A pane (in a window that is never shown) with a box above the section and a footer
    /// under it, laid out.
    @discardableResult
    private func install(_ section: PreferencesDisclosureSection) -> NSView {
        let root = PreferencesForm.makeBackground()
        let content = Form.installContentStack(in: root, paneWidth: paneWidth)
        let above = PreferencesGroupSection(width: boxWidth, rows: [PreferencesSwitchRow(title: "Above", target: nil, action: nil)])
        let footer = PreferencesGroupFooter(trailing: [Form.makePushButton(title: "Reset", target: nil, action: nil)])
        Form.add([above, section, footer], to: content)
        content.setCustomSpacing(Form.sectionSpacing, after: above)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: paneWidth, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = root
        self.window?.close()
        self.window = window
        relayout(section)
        return root
    }

    /// Fits the pane to its content again, as a pane does after the section changed.
    private func relayout(_ section: PreferencesDisclosureSection) {
        guard let root = window?.contentView else { return }
        root.layoutSubtreeIfNeeded()
        window?.setContentSize(root.fittingSize)
        root.layoutSubtreeIfNeeded()
    }

    /// Where a view sits in the pane by its alignment rectangle (the pane is not flipped).
    private func frame(of view: NSView) -> NSRect {
        let root = window!.contentView!
        return root.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
    }

    private func titleLineHeight() -> CGFloat {
        return Form.makeSectionTitle("X").fittingSize.height
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView) -> NSEvent {
        let location = view.convert(point, to: nil)
        return NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    private func click(_ title: PreferencesDisclosureTitle, releaseAt release: NSPoint? = nil) {
        let middle = NSPoint(x: title.bounds.midX, y: title.bounds.midY)
        title.mouseDown(with: mouse(.leftMouseDown, at: middle, in: title))
        title.mouseUp(with: mouse(.leftMouseUp, at: release ?? middle, in: title))
    }

    private func space() -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        )!
    }

    // MARK: - States

    func testWhileItCannotFoldItIsAnOrdinaryTitledSection() {
        let section = makeSection(collapsible: false)
        install(section)

        XCTAssertFalse(section.isCollapsible)
        XCTAssertTrue(section.showsBody)
        XCTAssertFalse(section.titleLabel.isHidden)
        XCTAssertTrue(section.disclosure.isHidden, "no chevron")
        XCTAssertFalse(section.body.isHidden)
        XCTAssertEqual(section.titleLabel.stringValue, "Directions")
        XCTAssertEqual(section.titleLabel.font, Form.sectionTitleFont)
        // The title at the rows' inset, the box under it as a titled section has it.
        XCTAssertEqual(frame(of: section.titleLabel).minX - frame(of: section).minX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(frame(of: section.titleLabel).minY - frame(of: section.body).maxY, Form.sectionTitleSpacing, accuracy: 0.5)
        XCTAssertEqual(frame(of: section.body).width, boxWidth, accuracy: 0.5)
        XCTAssertEqual(frame(of: section).minY, frame(of: section.body).minY, accuracy: 0.5, "the section ends with its box")

        // A click on where the title is changes nothing.
        section.toggle()
        XCTAssertTrue(section.showsBody)
        XCTAssertFalse(section.isExpanded)
    }

    func testASectionThatCanFoldStartsFoldedToItsTitleAndAChevron() {
        let plain = makeSection(collapsible: false)
        install(plain)
        // From the section's top: the panes differ in height.
        let plainTitle = frame(of: plain.titleLabel).offsetBy(dx: 0, dy: -frame(of: plain).maxY)

        let section = makeSection(collapsible: true)
        install(section)
        XCTAssertTrue(section.isCollapsible)
        XCTAssertFalse(section.isExpanded)
        XCTAssertFalse(section.showsBody)
        XCTAssertTrue(section.body.isHidden)
        XCTAssertTrue(section.titleLabel.isHidden)
        XCTAssertFalse(section.disclosure.isHidden)
        XCTAssertEqual(section.disclosure.label.stringValue, "Directions")
        XCTAssertEqual(section.disclosure.label.font, Form.sectionTitleFont)
        XCTAssertEqual(section.disclosure.chevron.turn, 0, "pointing right")
        // The title stands where the plain one stands: folding never moves it.
        let title = frame(of: section.disclosure.label).offsetBy(dx: 0, dy: -frame(of: section).maxY)
        XCTAssertEqual(title.minX, plainTitle.minX, accuracy: 0.5)
        XCTAssertEqual(title.maxY, plainTitle.maxY, accuracy: 0.5)
        XCTAssertEqual(title.height, plainTitle.height, accuracy: 0.5)
        // The chevron right after the title, on its middle line.
        let label = frame(of: section.disclosure.label)
        let chevron = frame(of: section.disclosure.chevron)
        XCTAssertEqual(chevron.minX - label.maxX, PreferencesDisclosureTitle.chevronSpacing, accuracy: 0.5)
        XCTAssertEqual(chevron.midY, label.midY, accuracy: 0.5)
        XCTAssertEqual(chevron.size, PreferencesDisclosureChevron.size)
        // Folded, the section is its title line alone.
        XCTAssertEqual(frame(of: section).height, titleLineHeight(), accuracy: 0.5)
    }

    func testAClickOpensItAndAnotherFoldsIt() {
        let section = makeSection(collapsible: true)
        install(section)
        var changes: [Bool] = []
        section.onExpandedChange = { expanded in
            changes.append(expanded)
            self.relayout(section)
        }

        click(section.disclosure)
        XCTAssertTrue(section.isExpanded)
        XCTAssertTrue(section.showsBody)
        XCTAssertFalse(section.body.isHidden)
        XCTAssertEqual(section.body.alphaValue, 1, "with Reduce Motion it shows at once")
        XCTAssertFalse(section.disclosure.isHidden, "the chevron stays while the section can fold")
        XCTAssertEqual(section.disclosure.chevron.turn, 1, "pointing down")
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(frame(of: section.disclosure.label).minY - frame(of: section.body).maxY, Form.sectionTitleSpacing, accuracy: 0.5)
        XCTAssertEqual(frame(of: section).minY, frame(of: section.body).minY, accuracy: 0.5)

        click(section.disclosure)
        XCTAssertFalse(section.isExpanded)
        XCTAssertTrue(section.body.isHidden)
        XCTAssertEqual(section.disclosure.chevron.turn, 0)
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(frame(of: section).height, titleLineHeight(), accuracy: 0.5)
    }

    func testAPressDimsTheTitleAndAReleaseBesideItDoesNothing() {
        let section = makeSection(collapsible: true)
        install(section)
        let title = section.disclosure
        let middle = NSPoint(x: title.bounds.midX, y: title.bounds.midY)

        title.mouseDown(with: mouse(.leftMouseDown, at: middle, in: title))
        XCTAssertTrue(title.isPressed)
        XCTAssertEqual(title.label.textColor, .secondaryLabelColor)
        XCTAssertEqual(title.chevron.color, .tertiaryLabelColor)
        let beside = NSPoint(x: title.bounds.maxX + 40, y: middle.y)
        title.mouseDragged(with: mouse(.leftMouseDragged, at: beside, in: title))
        XCTAssertFalse(title.isPressed, "dragged off, it lets go of its look")
        title.mouseUp(with: mouse(.leftMouseUp, at: beside, in: title))
        XCTAssertFalse(section.isExpanded, "let go beside the title: nothing")
        XCTAssertEqual(title.label.textColor, .labelColor)
        XCTAssertEqual(title.chevron.color, .secondaryLabelColor)
    }

    func testTheTitleAndTheChevronAreOneClickTarget() throws {
        let section = makeSection(collapsible: true)
        let root = install(section)
        for part in [section.disclosure.label, section.disclosure.chevron] as [NSView] {
            let point = root.convert(NSPoint(x: part.bounds.midX, y: part.bounds.midY), from: part)
            XCTAssertTrue(root.hitTest(point) === section.disclosure)
        }
    }

    func testWhatOpensCanBeUsedAndWhatIsFoldedCannot() throws {
        let section = makeSection(collapsible: true)
        let root = install(section)
        section.onExpandedChange = { _ in self.relayout(section) }
        let toggle = try XCTUnwrap(self.toggle)
        XCTAssertTrue(toggle.isHiddenOrHasHiddenAncestor)

        click(section.disclosure)
        XCTAssertFalse(toggle.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(toggle.isEnabled)
        let point = root.convert(NSPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), from: toggle)
        XCTAssertTrue(root.hitTest(point) === toggle, "the switch takes its click")
    }

    func testOnceItCannotFoldItShowsEverythingAndItStartsFoldedWhenItCanAgain() {
        let section = makeSection(collapsible: true)
        install(section)
        click(section.disclosure)
        XCTAssertTrue(section.isExpanded)

        section.isCollapsible = false
        XCTAssertTrue(section.showsBody)
        XCTAssertFalse(section.titleLabel.isHidden)
        XCTAssertTrue(section.disclosure.isHidden)

        section.isCollapsible = true
        XCTAssertFalse(section.isExpanded, "folded again")
        XCTAssertTrue(section.body.isHidden)
        XCTAssertEqual(section.disclosure.chevron.turn, 0)
        XCTAssertEqual(section.disclosure.accessibilityValue() as? NSNumber, 0)
    }

    // MARK: - Keyboard and VoiceOver

    func testSpaceOpensAndFoldsItAndTabReachesItAsItReachesAButton() {
        let section = makeSection(collapsible: true)
        install(section)
        let title = section.disclosure
        XCTAssertEqual(title.acceptsFirstResponder, NSApp.isFullKeyboardAccessEnabled, "as a button")
        XCTAssertEqual(title.focusRingType, .default)
        XCTAssertTrue(title.focusRingMaskBounds.contains(title.bounds), "the ring goes round the title and the chevron")

        title.keyDown(with: space())
        XCTAssertTrue(section.isExpanded)
        title.keyDown(with: space())
        XCTAssertFalse(section.isExpanded)
    }

    func testVoiceOverHearsADisclosureTriangleNamedByTheTitle() {
        let section = makeSection(collapsible: true)
        install(section)
        let title = section.disclosure
        XCTAssertTrue(title.isAccessibilityElement())
        XCTAssertEqual(title.accessibilityRole(), .disclosureTriangle)
        XCTAssertEqual(title.accessibilityLabel(), "Directions")
        XCTAssertEqual(title.accessibilityValue() as? NSNumber, 0, "collapsed")
        XCTAssertFalse(title.isAccessibilityExpanded())
        XCTAssertFalse(title.label.isAccessibilityElement(), "the title is said once")
        XCTAssertFalse(title.chevron.isAccessibilityElement())

        XCTAssertTrue(title.accessibilityPerformPress())
        XCTAssertTrue(section.isExpanded)
        XCTAssertEqual(title.accessibilityValue() as? NSNumber, 1, "expanded")
        XCTAssertTrue(title.isAccessibilityExpanded())

        XCTAssertTrue(title.accessibilityPerformPress())
        XCTAssertFalse(section.isExpanded)
        XCTAssertEqual(title.accessibilityValue() as? NSNumber, 0)
    }

    // MARK: - Motion

    func testWithReduceMotionTheChevronTurnsAtOnce() {
        let section = makeSection(collapsible: true, reducedMotion: true)
        install(section)
        click(section.disclosure)
        XCTAssertEqual(section.disclosure.chevron.turn, 1)
        XCTAssertEqual(section.body.alphaValue, 1)
    }

    func testWithoutReduceMotionTheChevronTurnsOverAFifthOfASecond() {
        XCTAssertEqual(PreferencesDisclosureSection.animationDuration, 0.2)
        let section = makeSection(collapsible: true, reducedMotion: false)
        install(section)
        click(section.disclosure)
        XCTAssertTrue(section.isExpanded)
        XCTAssertFalse(section.body.isHidden)
        XCTAssertEqual(section.disclosure.accessibilityValue() as? NSNumber, 1, "the state is at once what it ends as")

        // The turn and the fade end where they head for.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, section.disclosure.chevron.turn < 1 || section.body.alphaValue < 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(section.disclosure.chevron.turn, 1, accuracy: 0.001)
        XCTAssertEqual(section.body.alphaValue, 1, accuracy: 0.001)
    }

    // MARK: - Pictures

    /// Only when asked (`TEST_RUNNER_SCROLLIO_SHOTS_DIR`): the section in a pane between a
    /// box and a footer, at 2x, light and dark (`disclosure-section-<state>-<appearance>.png`):
    /// folded, open, and as an ordinary titled section.
    func testRenderTheSectionFoldedOpenAndPlain() throws {
        let directory = try RenderShots.directory(for: "the disclosure section")
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for state in ["folded", "open", "plain"] {
                let section = makeSection(collapsible: state != "plain")
                let root = install(section)
                window?.appearance = appearance
                if state == "open" {
                    section.setExpanded(true)
                }
                relayout(section)
                root.display()
                let rep = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: rep)
                let canvas = try XCTUnwrap(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width * 2), pixelsHigh: Int(root.bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ))
                canvas.size = root.bounds.size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
                appearance.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    root.bounds.fill()
                }
                rep.draw(in: root.bounds)
                NSGraphicsContext.restoreGraphicsState()
                let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("disclosure-section-\(state)-\(suffix).png"))
            }
        }
    }

    func testTheChevronIsDrawnTurnedByItsTurn() throws {
        // Drawn into a picture: right and down differ, and down is right turned a quarter.
        func picture(turn: CGFloat) throws -> NSBitmapImageRep {
            let chevron = PreferencesDisclosureChevron(frame: NSRect(origin: .zero, size: PreferencesDisclosureChevron.size))
            chevron.appearance = NSAppearance(named: .aqua)
            chevron.turn = turn
            let rep = try XCTUnwrap(chevron.bitmapImageRepForCachingDisplay(in: chevron.bounds))
            chevron.cacheDisplay(in: chevron.bounds, to: rep)
            return rep
        }
        /// The ink's extent: wider than tall points sideways.
        func extent(_ rep: NSBitmapImageRep) -> (width: Int, height: Int) {
            var xs: [Int] = [], ys: [Int] = []
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                    xs.append(x)
                    ys.append(y)
                }
            }
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return (0, 0) }
            return (maxX - minX + 1, maxY - minY + 1)
        }
        let rightPicture = try picture(turn: 0)
        let right = extent(rightPicture)
        let down = extent(try picture(turn: 1))
        // In the secondary label colour, as see-through as it: not the title's near-black.
        var strongest: CGFloat = 0
        for x in 0..<rightPicture.pixelsWide {
            for y in 0..<rightPicture.pixelsHigh {
                strongest = max(strongest, rightPicture.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        XCTAssertLessThan(strongest, 0.75)
        XCTAssertGreaterThan(right.width, 0)
        XCTAssertLessThan(right.width, right.height, "› is taller than wide")
        XCTAssertGreaterThan(down.width, down.height, "turned down it is wider than tall")
    }
}
