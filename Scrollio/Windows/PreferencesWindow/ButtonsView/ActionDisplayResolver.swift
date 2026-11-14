//
//  ActionDisplayResolver.swift
//  Mos
//  What the action pull-down of a button shows for a binding: a symbol and a name, as the
//  pull-downs of the Gestures pane, an app's icon and name, or a keyboard shortcut as text.
//  A keyboard shortcut the user gave a label (`ShortcutLabel`) shows its icon and its
//  name, and its keys after them in grey (`detail`).
//

import Cocoa

enum ActionPresentationKind: Equatable {
    case unbound
    case recordingPrompt
    case namedAction
    case keyCombo
    case openTarget
}

struct ActionPresentation {
    let kind: ActionPresentationKind
    let title: String
    /// Shown after the title, smaller in meaning and grey: the keys of a keyboard
    /// shortcut that has a name. Nil for everything else.
    let detail: String?
    /// An SF Symbol shown before the title.
    let symbolName: String?
    /// One character shown before the title instead of a symbol: the icon a user typed
    /// for a keyboard shortcut.
    let glyph: String?
    /// A picture shown before the title instead of a symbol (an app's icon).
    let image: NSImage?

    init(
        kind: ActionPresentationKind, title: String, detail: String? = nil, symbolName: String? = nil,
        glyph: String? = nil, image: NSImage? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.glyph = glyph
        self.image = image
    }

    /// What stands between the title and the detail.
    static let detailGap = "  "

    /// The title and what stands after it as one text ("Reload  ⇧⌘R"): what VoiceOver
    /// reads. (A menu item's title is its attributed title's text, so the two are the
    /// same text.)
    var plainTitle: String {
        return detail.map { title + Self.detailGap + $0 } ?? title
    }

    /// The title with the detail after it in the secondary colour, in `font`; nil when
    /// there is no detail (the plain title is all there is to show).
    func attributedTitle(font: NSFont) -> NSAttributedString? {
        guard let detail else { return nil }
        let text = NSMutableAttributedString(string: title + Self.detailGap, attributes: [.font: font])
        text.append(NSAttributedString(string: detail, attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }
}

/// What a row's pull-down shows (mutually exclusive). `.recordingPrompt` is the moment
/// "Keyboard Shortcut…" waits for a key; the others are a stored binding.
enum CellActionState: Equatable {
    case unbound
    case recordingPrompt
    case namedShortcut(SystemShortcut.Shortcut)
    case customBinding(name: String, label: ShortcutLabel? = nil)
    case openTarget(OpenTargetPayload)

    var hasBoundAction: Bool {
        switch self {
        case .unbound, .recordingPrompt:
            return false
        case .namedShortcut, .customBinding, .openTarget:
            return true
        }
    }

    /// The state of a stored binding. Order: open target, a named action, a keyboard
    /// shortcut, nothing.
    init(binding: ButtonBinding) {
        if let openTarget = binding.openTarget {
            self = .openTarget(openTarget)
            return
        }
        if let shortcut = binding.systemShortcut {
            self = .namedShortcut(shortcut)
            return
        }
        if binding.isCustomBinding {
            self = .customBinding(name: binding.systemShortcutName, label: binding.label)
            return
        }
        self = .unbound
    }
}

struct ActionDisplayResolver {

    func resolve(state: CellActionState) -> ActionPresentation {
        switch state {
        case .unbound:
            return ActionPresentation(kind: .unbound, title: NSLocalizedString("unbound", comment: ""))
        case .recordingPrompt:
            return ActionPresentation(kind: .recordingPrompt, title: NSLocalizedString("custom-recording-prompt", comment: ""))
        case .namedShortcut(let shortcut):
            return namedActionPresentation(for: shortcut)
        case .openTarget(let payload):
            return openTargetPresentation(for: payload)
        case .customBinding(let name, let label):
            // A recorded shortcut that equals a named action shows as that action, unless
            // the user called it something of their own.
            if label == nil, let shortcut = SystemShortcut.displayShortcut(matchingBindingName: name) {
                return namedActionPresentation(for: shortcut)
            }
            if let custom = customBindingPresentation(for: name, label: label) {
                return custom
            }
            return ActionPresentation(kind: .unbound, title: NSLocalizedString("unbound", comment: ""))
        }
    }

    /// The same, from the separate pieces.
    func resolve(
        shortcut: SystemShortcut.Shortcut?,
        customBindingName: String?,
        isRecording: Bool,
        openTarget: OpenTargetPayload? = nil
    ) -> ActionPresentation {
        let state: CellActionState = {
            if isRecording { return .recordingPrompt }
            if let openTarget { return .openTarget(openTarget) }
            if let shortcut { return .namedShortcut(shortcut) }
            if let customBindingName { return .customBinding(name: customBindingName) }
            return .unbound
        }()
        return resolve(state: state)
    }

    /// The name of the action, for texts ("No action" is the caller's).
    func actionName(of binding: ButtonBinding) -> String? {
        let presentation = resolve(state: CellActionState(binding: binding))
        return presentation.kind == .unbound ? nil : presentation.title
    }

    private func namedActionPresentation(for shortcut: SystemShortcut.Shortcut) -> ActionPresentation {
        ActionPresentation(kind: .namedAction, title: shortcut.localizedName, symbolName: shortcut.symbolName)
    }

    private func openTargetPresentation(for payload: OpenTargetPayload) -> ActionPresentation {
        let workspace = NSWorkspace.shared
        // What a press opens: the stored path first (ShortcutExecutor.applicationURL).
        let resolvedURL = ShortcutExecutor.applicationURL(
            for: payload,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            urlForBundleIdentifier: { workspace.urlForApplication(withBundleIdentifier: $0) }
        )

        guard let url = resolvedURL else {
            // Gone: the file's name and a marker.
            let basename = (payload.path as NSString).lastPathComponent
            let staleTag = NSLocalizedString("open-target-placeholder-stale", comment: "")
            let title = basename.isEmpty ? staleTag : "\(basename) \(staleTag)"
            return ActionPresentation(kind: .openTarget, title: title, symbolName: "exclamationmark.triangle")
        }
        let title: String
        if payload.kind == .application, let bundle = Bundle(url: url) {
            title = bundle.localizedDisplayName
                ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        } else {
            title = url.lastPathComponent
        }
        return ActionPresentation(kind: .openTarget, title: title, image: workspace.icon(forFile: url.path))
    }

    /// A recorded shortcut as its keys ("⌨ ⇧⌘R"). With a label: its icon in the place of
    /// the keyboard symbol, and its name with the keys after it; with only one of the two
    /// the other stays as it is without a label.
    private func customBindingPresentation(for customBindingName: String, label: ShortcutLabel?) -> ActionPresentation? {
        guard let payload = ButtonBinding.normalizedCustomBindingDescriptor(from: customBindingName) else {
            return nil
        }
        let text = ButtonTriggerNaming.shortcutText(type: payload.type, code: payload.code, modifiers: payload.modifiers)
        let label = ShortcutLabel.kept(label, for: customBindingName)
        var symbolName: String? = payload.type == .mouse ? "computermouse" : "keyboard"
        var glyph: String?
        switch label?.icon {
        case .symbol(let name)? where ShortcutRingFace.hasSymbol(named: name):
            symbolName = name
        case .character(let character)?:
            symbolName = nil
            glyph = character
        case .symbol?, nil:
            break
        }
        return ActionPresentation(
            kind: .keyCombo,
            title: label?.name ?? text,
            detail: label?.name == nil ? nil : text,
            symbolName: symbolName,
            glyph: glyph
        )
    }
}

extension Bundle {
    var localizedDisplayName: String? {
        return localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? localizedInfoDictionary?["CFBundleName"] as? String
    }
}
