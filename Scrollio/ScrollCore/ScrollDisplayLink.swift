//
//  ScrollDisplayLink.swift
//  Scrollio
//
//  The display link ScrollPoster posts its frames with, behind a small protocol: a test can
//  stand in for a display (no display link can be made while the display is off), and the
//  rules around the link (when it is made, replaced, started and stopped) can be tested.
//

import Cocoa

/// What ScrollPoster needs of a display link. Used on the main thread; a link that runs calls
/// its output callback on a thread of its own.
protocol ScrollDisplayLink: AnyObject {
    var isRunning: Bool { get }
    /// - Returns: `kCVReturnSuccess` when the link runs now.
    func start() -> CVReturn
    func stop()
    /// Ties the link to the display the pointer is on, before a scroll starts.
    ///
    /// A display link fires in step with one display. Two displays, even at the same rate,
    /// refresh at different moments that drift against each other, so frames timed for the
    /// main display reach a window on the other one now early, now late: every so often a
    /// refresh shows no movement and the next one shows twice as much.
    func followDisplayUnderPointer()
    /// The link's nominal rate (Hz); -1 when it has none.
    var nominalHz: Double { get }
    /// The rate (Hz) of the display the link follows; 0 when it is not known.
    var followedDisplayHz: Double { get }
}

/// The app's display link: a `CVDisplayLink` for the active displays.
final class ScrollCVDisplayLink: ScrollDisplayLink {

    let link: CVDisplayLink

    init(_ link: CVDisplayLink) {
        self.link = link
    }

    /// A link for the active displays that calls `output` for every frame once it runs.
    /// - Returns: the link, or nil with CoreVideo's result when none can be made (-6661,
    ///   `kCVReturnInvalidArgument`, while no display is on).
    static func make(output: @escaping CVDisplayLinkOutputCallback) -> (link: ScrollDisplayLink?, result: CVReturn) {
        var made: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&made)
        guard result == kCVReturnSuccess, let link = made else {
            return (nil, result)
        }
        CVDisplayLinkSetOutputCallback(link, output, nil)
        return (ScrollCVDisplayLink(link), result)
    }

    var isRunning: Bool {
        return CVDisplayLinkIsRunning(link)
    }

    func start() -> CVReturn {
        return CVDisplayLinkStart(link)
    }

    func stop() {
        CVDisplayLinkStop(link)
    }

    func followDisplayUnderPointer() {
        guard let location = CGEvent(source: nil)?.location else { return }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0,
              display != CVDisplayLinkGetCurrentCGDisplay(link) else { return }
        CVDisplayLinkSetCurrentCGDisplay(link, display)
    }

    /// CVDisplayLink 当前绑定显示器的标称刷新率 (Hz); 无效返回 -1
    var nominalHz: Double {
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        // 无效/indefinite 周期时 timeValue 或 timeScale 为 0
        guard period.timeValue != 0, period.timeScale != 0 else { return -1 }
        let seconds = Double(period.timeValue) / Double(period.timeScale)
        return seconds > 0 ? 1.0 / seconds : -1
    }

    var followedDisplayHz: Double {
        return CGDisplayCopyDisplayMode(CVDisplayLinkGetCurrentCGDisplay(link))?.refreshRate ?? 0
    }
}
