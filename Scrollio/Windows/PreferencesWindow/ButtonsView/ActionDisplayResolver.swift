//
//  ActionDisplayResolver.swift
//  Mos
//  What the action pull-down of a button shows for a binding: a symbol and a name, as the
//  pull-downs of the Gestures pane, an app's icon and name, or a keyboard shortcut as text.
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
    /// An SF Symbol shown before the title.
    let symbolName: String?
    /// A picture shown before the title instead of a symbol (an app's icon).
    let image: NSImage?

    init(kind: ActionPresentationKind, title: String, symbolName: String? = nil, image: NSImage? = nil) {
        self.kind = kind
        self.title = title
        self.symbolName = symbolName
        self.image = image
    }
}

/// What a row's pull-down shows (mutually exclusive). `.recordingPrompt` is the moment
/// "Keyboard Shortcut…" waits for a key; the others are a stored binding.
enum CellActionState: Equatable {
    case unbound
    case recordingPrompt
    case namedShortcut(SystemShortcut.Shortcut)
    case customBinding(name: String)
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
            self = .customBinding(name: binding.systemShortcutName)
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
        case .customBinding(let name):
            // A recorded shortcut that equals a named action shows as that action.
            if let shortcut = SystemShortcut.displayShortcut(matchingBindingName: name) {
                return namedActionPresentation(for: shortcut)
            }
            if let custom = customBindingPresentation(for: name) {
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

    private func customBindingPresentation(for customBindingName: String) -> ActionPresentation? {
        guard let payload = ButtonBinding.normalizedCustomBindingDescriptor(from: customBindingName) else {
            return nil
        }
        let text = ButtonTriggerNaming.shortcutText(type: payload.type, code: payload.code, modifiers: payload.modifiers)
        return ActionPresentation(
            kind: .keyCombo,
            title: text,
            symbolName: payload.type == .mouse ? "computermouse" : "keyboard"
        )
    }
}

extension Bundle {
    var localizedDisplayName: String? {
        return localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? localizedInfoDictionary?["CFBundleName"] as? String
    }
}
