//
//  MonitorLogStore.swift
//  Mos
//

import Foundation

enum MonitorLogChannel: String, CaseIterable {
    case buttonEvent = "Button Event"
}

final class MonitorLogStore {

    private let previewLineLimit: Int
    /// The most lines kept per channel. The store used to grow for as long as the window
    /// stayed open (pointer moves alone add hundreds of lines a second).
    let lineLimit: Int
    private var linesByChannel: [MonitorLogChannel: [String]] = [:]

    init(previewLineLimit: Int = 200, lineLimit: Int = 20_000) {
        self.previewLineLimit = max(1, previewLineLimit)
        self.lineLimit = max(self.previewLineLimit, lineLimit)
    }

    func append(_ line: String, to channel: MonitorLogChannel) {
        guard !line.isEmpty else { return }
        linesByChannel[channel, default: []].append(line)
        // The oldest lines go, a tenth at a time so that not every line pays for it.
        if let count = linesByChannel[channel]?.count, count > lineLimit + lineLimit / 10 {
            linesByChannel[channel]?.removeFirst(count - lineLimit)
        }
    }

    func lineCount(for channel: MonitorLogChannel) -> Int {
        return linesByChannel[channel]?.count ?? 0
    }

    func previewText(for channel: MonitorLogChannel) -> String {
        let lines = linesByChannel[channel] ?? []
        return lines.suffix(previewLineLimit).reversed().joined(separator: "\n")
    }

    func exportText(for channel: MonitorLogChannel) -> String {
        (linesByChannel[channel] ?? []).joined(separator: "\n")
    }

    func clear(_ channel: MonitorLogChannel? = nil) {
        guard let channel else {
            linesByChannel.removeAll()
            return
        }
        linesByChannel[channel] = []
    }
}
