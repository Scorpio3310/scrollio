//
//  ShortcutIconChooserTests.swift
//  ScrollioTests
//
//  The recorder's details card and the chooser of icons that opens from its well: the
//  card keeps one size whatever it holds, the well shows the icon and says it, Delete on
//  the well takes the icon away; the chooser searches, offers one typed character first,
//  chooses and closes, shows "Remove Icon" only when there is an icon, closes alone on
//  Esc; and the popover around the card does not close for a click in the chooser (it is
//  semi-transient while the chooser is open, transient again afterwards) but closes with
//  it for a click outside both.
//
//  Nothing here is shown on the screen: the popovers are built without a window (the
//  chooser's is never shown) and the keys are events made in the test, never posted.
//

import XCTest
@testable import Scrollio_Debug

final class ShortcutIconChooserTests: XCTestCase {

    private let reload = ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise"))
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.contentView = nil }
        windows = []
        super.tearDown()
    }

    /// The card in a window that is never shown, so that the keyboard has a place in it.
    private func inWindow(_ popover: KeyPopover) throws -> NSWindow {
        let content = try XCTUnwrap(popover.testingContentView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize), styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(content)
        windows.append(window)
        return window
    }

    private func details(_ label: ShortcutLabel?) throws -> (KeyPopover, ShortcutLabelEditorView) {
        let popover = KeyPopover()
        popover.announce = { _ in }
        popover.testingPrepareDetails(keys: ["⇧", "⌘", "R"], label: label)
        let editor = try XCTUnwrap(popover.labelEditor)
        editor.presentChooser = { _, _ in }
        return (popover, editor)
    }

    private func size(of popover: KeyPopover) throws -> NSSize {
        let content = try XCTUnwrap(popover.testingContentView)
        content.layoutSubtreeIfNeeded()
        XCTAssertFalse(content.hasAmbiguousLayout)
        return content.fittingSize
    }

    private func chooser(_ icon: ShortcutLabel.Icon?) -> ShortcutIconChooserController {
        let chooser = ShortcutIconChooserController(icon: icon)
        chooser.openCharacterPalette = { XCTFail("the viewer is not opened here") }
        _ = chooser.view
        return chooser
    }

    private func names(_ choices: ShortcutIconChoices) -> [String] {
        return choices.sections.flatMap { $0.entries }.map { entry in
            switch entry {
            case .symbol(let symbol): return symbol.name
            case .character(let text): return "“\(text)”"
            }
        }
    }

    private func key(_ code: UInt16, _ characters: String) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
    }

    // MARK: The card

    /// One short card: the same size with nothing, a name, a symbol, a character, and while
    /// the chooser is open. About 312 × 190.
    func testTheCardIsTheSameSizeInEveryState() throws {
        let cases: [ShortcutLabel?] = [
            nil,
            ShortcutLabel(name: "Reload", icon: nil),
            ShortcutLabel(name: nil, icon: .symbol("arrow.clockwise")),
            reload,
            ShortcutLabel(name: "Sync everything", icon: .character("🔄")),
            ShortcutLabel(name: String(repeating: "W", count: ShortcutLabel.maximumNameLength), icon: .character("W")),
        ]
        var sizes: [NSSize] = []
        for label in cases {
            let (popover, editor) = try details(label)
            sizes.append(try size(of: popover))
            editor.openChooser()
            XCTAssertTrue(editor.isChoosingIcon)
            sizes.append(try size(of: popover))
            editor.closeChooser()
        }
        let first = try XCTUnwrap(sizes.first)
        for size in sizes {
            XCTAssertEqual(size.width, first.width, accuracy: 0.5)
            XCTAssertEqual(size.height, first.height, accuracy: 0.5)
        }
        XCTAssertEqual(first.width, 312, accuracy: 1)
        XCTAssertGreaterThan(first.height, 150)
        XCTAssertLessThan(first.height, 215)
    }

    /// The well and the name are one row, the well left, 36 pt square.
    func testTheWellStandsLeftOfTheName() throws {
        let (popover, editor) = try details(reload)
        let content = try XCTUnwrap(popover.testingContentView)
        content.setFrameSize(try size(of: popover))
        content.layoutSubtreeIfNeeded()
        let well = editor.iconWell.frame
        let field = editor.nameField.frame
        XCTAssertEqual(well.width, ShortcutIconWell.side)
        XCTAssertEqual(well.height, ShortcutIconWell.side)
        XCTAssertLessThan(well.maxX, field.minX)
        XCTAssertEqual(well.midY, field.midY, accuracy: 1)
        XCTAssertLessThan(editor.noteLabel.frame.maxY, well.minY + 0.5, "the note is under the row")
        XCTAssertLessThan(editor.doneButton.frame.maxY, editor.noteLabel.frame.minY, "the buttons under the note")
        XCTAssertGreaterThan(editor.doneButton.frame.minX, editor.recordAgainButton.frame.maxX, "Done on the right")
        // Tab from the name goes to the well.
        XCTAssertTrue(editor.nameField.nextKeyView === editor.iconWell)
        XCTAssertTrue(editor.iconWell.nextKeyView === editor.recordAgainButton)
        let chooser = ShortcutIconChooserController(icon: nil)
        _ = chooser.view
        XCTAssertTrue(chooser.searchField.nextKeyView === chooser.grid, "from the search into the grid")
    }

    /// The well shows each kind of icon, and VoiceOver hears what it is.
    func testTheWellShowsEachKindAndSaysIt() throws {
        let well = ShortcutIconWell()
        XCTAssertEqual(well.accessibilityLabel(), "Choose Icon")
        XCTAssertEqual(well.toolTip, "Choose Icon")
        XCTAssertNotNil(well.image, "a quiet plus")
        XCTAssertEqual(well.contentTintColor, .secondaryLabelColor)

        well.show(.symbol("arrow.clockwise"))
        XCTAssertEqual(well.accessibilityLabel(), "Icon: arrow clockwise")
        XCTAssertEqual(well.contentTintColor, .controlAccentColor)
        XCTAssertEqual(well.image?.size.height ?? 0, 18, accuracy: 6, "about 18 pt")

        well.show(.character("🔄"))
        XCTAssertEqual(well.accessibilityLabel(), "Icon: 🔄")
        XCTAssertNil(well.contentTintColor, "an emoji in its own colours")
        XCTAssertNotNil(well.image)

        well.show(.symbol("no.such.symbol.anywhere"))
        XCTAssertNotNil(well.image, "a symbol this Mac does not have still shows something")
        XCTAssertTrue(well.acceptsFirstResponder)
        XCTAssertTrue(well.canBecomeKeyView, "Tab stops at it")
    }

    /// Delete (or Forward Delete) on the focused well takes the icon away; the name stays.
    func testDeleteOnTheWellRemovesTheIcon() throws {
        let (popover, editor) = try details(reload)
        editor.iconWell.keyDown(with: try key(51, "\u{7F}"))
        XCTAssertNil(editor.icon)
        XCTAssertEqual(popover.editedLabel, ShortcutLabel(name: "Reload", icon: nil))
        XCTAssertEqual(editor.iconWell.accessibilityLabel(), "Choose Icon")

        editor.choose(.character("R"))
        editor.iconWell.keyDown(with: try key(117, "\u{F728}"))
        XCTAssertNil(editor.icon)
    }

    // MARK: The chooser

    /// A search shows only what it finds, in its groups; nothing found: the grid gives way
    /// to a symbol and two lines, and the chooser keeps its size.
    func testTheSearchFiltersTheSymbols() throws {
        let chooser = chooser(nil)
        XCTAssertEqual(names(chooser.choices), ShortcutIconSet.all.map { $0.name })
        XCTAssertEqual(chooser.choices.sections.map { $0.title }, ShortcutIconSet.groups.map { $0.title })
        XCTAssertFalse(chooser.scrollView.isHidden)
        XCTAssertTrue(chooser.noMatchView.isHidden)
        chooser.view.layoutSubtreeIfNeeded()
        let full = chooser.view.fittingSize
        XCTAssertEqual(full.width, ShortcutIconChooserLayout.width)
        XCTAssertEqual(full.width, 304)

        chooser.search("reload")
        XCTAssertEqual(names(chooser.choices), ["arrow.clockwise"])
        XCTAssertEqual(chooser.grid.selectionIndexPaths, [IndexPath(item: 0, section: 0)], "the first result is ready for Return")
        chooser.search("zoom")
        XCTAssertEqual(names(chooser.choices), ["plus.magnifyingglass", "minus.magnifyingglass"])
        chooser.search("zzzq")
        XCTAssertTrue(chooser.choices.isEmpty)
        XCTAssertTrue(chooser.scrollView.isHidden)
        XCTAssertFalse(chooser.noMatchView.isHidden)
        XCTAssertTrue(chooser.grid.selectionIndexPaths.isEmpty)
        chooser.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(chooser.view.fittingSize, full, "the same size without a result")
        chooser.search("")
        XCTAssertEqual(names(chooser.choices).count, ShortcutIconSet.all.count)
    }

    /// One character that can be seen (typed, pasted, or from the Emoji & Symbols viewer)
    /// is offered first, as a row of its own; an emoji or a sign finds no symbol.
    func testASingleTypedCharacterIsOfferedFirst() throws {
        let emoji = ShortcutIconChoices.matching("🔄")
        XCTAssertEqual(names(emoji), ["“🔄”"])
        XCTAssertNil(emoji.sections.first?.title, "no group's name over it")

        let letter = ShortcutIconChoices.matching(" R ")
        XCTAssertEqual(letter.first, .character("R"))
        XCTAssertGreaterThan(names(letter).count, 1, "then the symbols the letter begins")
        XCTAssertTrue(names(letter).contains("arrow.clockwise"), "reload")

        XCTAssertEqual(names(ShortcutIconChoices.matching("👨‍👩‍👧")), ["“👨‍👩‍👧”"], "one character of several scalars")
        XCTAssertNil(ShortcutIconChoices.matching("ab").indexPath(of: .character("a")), "two characters are a search")
        XCTAssertTrue(ShortcutIconChoices.matching("\u{200E}").isEmpty, "nothing that can be seen")

        let chooser = chooser(nil)
        chooser.search("🔄")
        XCTAssertEqual(chooser.grid.selectionIndexPaths, [IndexPath(item: 0, section: 0)])
        XCTAssertEqual(chooser.grid.numberOfSections, 1)
        XCTAssertEqual(chooser.grid.numberOfItems(inSection: 0), 1)
        let row = chooser.collectionView(chooser.grid, layout: chooser.grid.collectionViewLayout!, sizeForItemAt: IndexPath(item: 0, section: 0))
        XCTAssertEqual(row.width, ShortcutIconChooserLayout.width - 2 * ShortcutIconChooserLayout.inset, "a row across the grid")
        XCTAssertEqual(String(format: NSLocalizedString("key-recorder-icon-use-character", comment: ""), "🔄"), "Use “🔄”")
    }

    /// Return in the search field, Return in the grid or a click (the grid's choice of a
    /// place) choose: the editor has the icon, the well shows it, the chooser is closed.
    func testChoosingUpdatesTheLabelAndClosesTheChooser() throws {
        let (popover, editor) = try details(ShortcutLabel(name: "Reload", icon: nil))
        editor.iconWell.performClick(nil)
        var chooser = try XCTUnwrap(editor.chooser)
        chooser.searchField.stringValue = "share"
        chooser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: chooser.searchField))
        XCTAssertTrue(chooser.control(chooser.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(popover.editedLabel, ShortcutLabel(name: "Reload", icon: .symbol("square.and.arrow.up")))
        XCTAssertFalse(editor.isChoosingIcon)
        XCTAssertEqual(editor.iconWell.accessibilityLabel(), "Icon: square and arrow up")

        editor.iconWell.performClick(nil)
        chooser = try XCTUnwrap(editor.chooser)
        XCTAssertEqual(chooser.grid.selectionIndexPaths, [IndexPath(item: 3, section: 0)], "the icon of the moment is selected")
        // A click on the hammer (the grid hands the place it was clicked at on).
        let hammer = try XCTUnwrap(chooser.choices.indexPath(of: .symbol("hammer")))
        chooser.grid.onChooseAt?(hammer)
        XCTAssertEqual(editor.icon, .symbol("hammer"))
        XCTAssertFalse(editor.isChoosingIcon)

        // Return in the grid chooses what is selected there.
        editor.iconWell.performClick(nil)
        chooser = try XCTUnwrap(editor.chooser)
        chooser.grid.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        chooser.grid.keyDown(with: try key(36, "\r"))
        XCTAssertEqual(editor.icon, .symbol("arrow.clockwise"))
        XCTAssertFalse(editor.isChoosingIcon)
        XCTAssertEqual(popover.testingBehavior, .transient)
    }

    /// "Remove Icon" is there only when there is an icon (hidden, not off), and takes it
    /// away.
    func testRemoveIconOnlyWithAnIcon() throws {
        XCTAssertTrue(chooser(nil).removeButton.isHidden)
        XCTAssertFalse(chooser(.symbol("star")).removeButton.isHidden)
        XCTAssertFalse(chooser(.character("R")).removeButton.isHidden)
        XCTAssertEqual(chooser(.symbol("star")).removeButton.title, "Remove Icon")
        XCTAssertTrue(chooser(.symbol("star")).removeButton.isEnabled)

        let (popover, editor) = try details(reload)
        editor.openChooser()
        try XCTUnwrap(editor.chooser).removeButton.performClick(nil)
        XCTAssertEqual(popover.editedLabel, ShortcutLabel(name: "Reload", icon: nil))
        XCTAssertFalse(editor.isChoosingIcon)
    }

    /// "Emoji & Symbols…" opens the system's viewer (it types into the search field).
    func testTheEmojiButtonOpensTheSystemsViewer() throws {
        let chooser = ShortcutIconChooserController(icon: nil)
        var opened = 0
        chooser.openCharacterPalette = { opened += 1 }
        _ = chooser.view
        XCTAssertEqual(chooser.emojiButton.title, "Emoji & Symbols…")
        chooser.emojiButton.performClick(nil)
        XCTAssertEqual(opened, 1)
    }

    /// Esc closes the chooser and nothing else: the card stays, as it was, and nothing is
    /// told closed. In the search field and in the grid alike.
    func testEscClosesTheChooserOnly() throws {
        let (popover, editor) = try details(reload)
        var closed = 0
        popover.onClose = { closed += 1 }
        editor.openChooser()
        var chooser = try XCTUnwrap(editor.chooser)
        XCTAssertTrue(chooser.control(chooser.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertFalse(editor.isChoosingIcon)
        XCTAssertEqual(popover.testingBehavior, .transient, "the card is there, transient again")
        XCTAssertEqual(closed, 0)
        XCTAssertEqual(popover.editedLabel, reload)

        editor.openChooser()
        chooser = try XCTUnwrap(editor.chooser)
        chooser.grid.keyDown(with: try key(53, "\u{1B}"))
        XCTAssertFalse(editor.isChoosingIcon)
        XCTAssertEqual(popover.testingBehavior, .transient)
        XCTAssertEqual(closed, 0)
        XCTAssertEqual(popover.editedLabel, reload)
    }

    // MARK: The popover in a popover

    /// While the chooser is open the card's popover is semi-transient: a click in the
    /// chooser is outside it, and must not close it. Afterwards it is transient again.
    func testTheCardIsSemiTransientWhileTheChooserIsOpen() throws {
        let (popover, editor) = try details(reload)
        XCTAssertEqual(popover.testingBehavior, .transient)
        var shownAt: NSView?
        var behaviorWhenShown: NSPopover.Behavior?
        editor.presentChooser = { chooserPopover, anchor in
            shownAt = anchor
            behaviorWhenShown = popover.testingBehavior
            XCTAssertEqual(chooserPopover.behavior, .transient, "the chooser closes for a click outside it")
        }
        editor.openChooser()
        XCTAssertTrue(shownAt === editor.iconWell, "it points at the well")
        XCTAssertEqual(behaviorWhenShown, .semitransient, "before the chooser shows")
        XCTAssertEqual(popover.testingBehavior, .semitransient)
        editor.openChooser()
        XCTAssertEqual(popover.testingBehavior, .semitransient, "a second open changes nothing")
        editor.closeChooser()
        XCTAssertEqual(popover.testingBehavior, .transient)

        // Showing the details again (after Record Again) closes it too, and leaves the
        // popover transient.
        editor.openChooser()
        popover.turnToDetails(label: reload)
        XCTAssertFalse(editor.isChoosingIcon)
        XCTAssertEqual(popover.testingBehavior, .transient)
    }

    /// Closed by a click outside both popovers (or with the app no longer in front), the
    /// chooser takes the card with it, and the name and the icon are kept. Closed for a
    /// click in either popover, or by Esc, it leaves the card.
    func testAClickOutsideBothClosesBoth() throws {
        let rule = ShortcutLabelEditorView.closesParent
        XCTAssertTrue(rule(5, 2, 3, true), "a click in the settings window")
        XCTAssertFalse(rule(2, 2, 3, true), "a click in the card")
        XCTAssertFalse(rule(3, 2, 3, true), "a click in the chooser")
        XCTAssertFalse(rule(nil, 2, 3, true), "Esc, Return, a choice")
        XCTAssertTrue(rule(nil, 2, 3, false), "another app came forward")

        let (popover, editor) = try details(reload)
        var closed = 0
        var keptLabel: ShortcutLabel?
        popover.onClose = { [unowned popover] in
            closed += 1
            keptLabel = popover.editedLabel
        }
        editor.openChooser()
        editor.choose(.character("R"))
        editor.testingCloseChooserAsTheSystemDoes(closesParent: true)
        XCTAssertFalse(editor.isChoosingIcon)
        XCTAssertNil(popover.testingBehavior, "the card is gone too")
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(keptLabel, ShortcutLabel(name: "Reload", icon: .character("R")))

        let (other, otherEditor) = try details(reload)
        otherEditor.openChooser()
        otherEditor.testingCloseChooserAsTheSystemDoes(closesParent: false)
        XCTAssertEqual(other.testingBehavior, .transient, "a click in the card leaves it")
    }

    /// The card closing (a click in the settings window, "Done", the pane) closes the
    /// chooser with it.
    func testTheCardClosingClosesTheChooser() throws {
        let (popover, editor) = try details(reload)
        editor.openChooser()
        popover.testingCloseAsTheUserDoes()
        XCTAssertFalse(editor.isChoosingIcon)

        let (done, doneEditor) = try details(reload)
        doneEditor.openChooser()
        done.hide()
        XCTAssertFalse(doneEditor.isChoosingIcon)
    }


    /// Return with nothing typed in the search and nothing selected (the icon is a typed
    /// character, a symbol that is not among these, or there is none) chooses nothing: the
    /// chooser closes as for Esc, and the icon stays. Something typed: Return takes the
    /// first that was found.
    func testReturnWithNothingChosenKeepsTheIcon() throws {
        let icons: [ShortcutLabel.Icon?] = [.character("🔄"), .symbol("tortoise"), nil]
        for icon in icons {
            let (popover, editor) = try details(ShortcutLabel(name: "Reload", icon: icon))
            var closed = 0
            popover.onClose = { closed += 1 }
            editor.openChooser()
            let chooser = try XCTUnwrap(editor.chooser)
            XCTAssertTrue(chooser.grid.selectionIndexPaths.isEmpty, "\(String(describing: icon)) is not among the symbols")
            XCTAssertTrue(chooser.control(chooser.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertEqual(editor.icon, icon, "the icon stays")
            XCTAssertFalse(editor.isChoosingIcon, "the chooser closes")
            XCTAssertEqual(closed, 0, "the card stays")
            XCTAssertEqual(popover.testingBehavior, .transient)
        }

        let (_, editor) = try details(ShortcutLabel(name: "Reload", icon: .character("🔄")))
        editor.openChooser()
        let chooser = try XCTUnwrap(editor.chooser)
        chooser.searchField.stringValue = "hammer"
        chooser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: chooser.searchField))
        XCTAssertTrue(chooser.control(chooser.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(editor.icon, .symbol("hammer"))
    }

    /// The card going away (a click in the settings window, Done, the pane leaving) closes
    /// the chooser without giving the keyboard back to the card: its window is not made
    /// the key one again while it closes.
    func testTheCardClosingGivesNothingOfItTheKeyboard() throws {
        let (popover, editor) = try details(reload)
        let window = try inWindow(popover)
        editor.openChooser()
        window.makeFirstResponder(nil)
        popover.testingCloseAsTheUserDoes()
        XCTAssertFalse(editor.isChoosingIcon)
        XCTAssertFalse(window.firstResponder === editor.iconWell, "closed by the system")

        let (done, doneEditor) = try details(reload)
        let doneWindow = try inWindow(done)
        doneEditor.openChooser()
        doneWindow.makeFirstResponder(nil)
        done.hide()
        XCTAssertFalse(doneEditor.isChoosingIcon)
        XCTAssertFalse(doneWindow.firstResponder === doneEditor.iconWell, "closed by the app")
    }

    // MARK: Layout of the chooser

    /// Eight columns of 32 pt cells; the grid's room ends in the middle of a row, so it
    /// reads as "scrolls"; the chosen symbol is selected and scrolled into view on open.
    func testTheGridShowsEightColumnsAndTheChosenSymbol() throws {
        let chooser = chooser(.symbol("hammer"))
        let view = chooser.view
        view.setFrameSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        let flow = try XCTUnwrap(chooser.grid.collectionViewLayout as? NSCollectionViewFlowLayout)
        let row = (0..<8).compactMap { flow.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
        XCTAssertEqual(row.count, 8)
        XCTAssertEqual(Set(row.map { $0.minY }).count, 1, "eight in the first row")
        XCTAssertEqual(row.first?.width, 32)
        let ninth = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: 8, section: 0))?.frame)
        XCTAssertGreaterThan(ninth.minY, row[0].minY, "the ninth starts the next row")
        XCTAssertEqual(chooser.scrollView.frame.height, ShortcutIconChooserLayout.gridHeight)

        // The visible room cuts the first row of the third group in its middle.
        let third = try XCTUnwrap(flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 2))?.frame)
        XCTAssertEqual(third.midY, ShortcutIconChooserLayout.gridHeight, accuracy: 1, "cut through a row")

        let hammer = try XCTUnwrap(chooser.choices.indexPath(of: .symbol("hammer")))
        XCTAssertEqual(chooser.grid.selectionIndexPaths, [hammer])
        let frame = try XCTUnwrap(flow.layoutAttributesForItem(at: hammer)?.frame)
        XCTAssertTrue(chooser.scrollView.documentVisibleRect.contains(frame), "the chosen symbol is in view")
    }
}
