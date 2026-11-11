import Cocoa

class ScrollSmoothDetailSettingsPopoverViewController: AdaptivePopover, ScrollOptionsContextProviding {

    @IBOutlet weak var verticalSmoothCheckBox: NSButton?
    @IBOutlet weak var horizontalSmoothCheckBox: NSButton?
    @IBOutlet weak var simulateTrackpadCheckBox: NSButton?

    var currentTargetApplication: Application?
    var onOptionsChanged: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        syncViewWithOptions()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncViewWithOptions()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    @IBAction func verticalSmoothToggle(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smoothVertical = sender.state == .on
        syncViewWithOptions()
        onOptionsChanged?()
    }

    @IBAction func horizontalSmoothToggle(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smoothHorizontal = sender.state == .on
        syncViewWithOptions()
        onOptionsChanged?()
    }

    /// Each state has its own Duration (OPTIONS_SCROLL_DEFAULT.setTrackpadStyleEvents); the
    /// slider stays free in both.
    @IBAction func simulateTrackpadToggle(_ sender: NSButton) {
        getTargetApplicationScrollOptions().setTrackpadStyleEvents(
            sender.state == .on,
            glideFromMomentum: Options.shared.scrollTuning.momentum != nil
        )
        syncViewWithOptions()
        onOptionsChanged?()
    }

    private func syncViewWithOptions() {
        updateSimulateTrackpadControl(simulateTrackpadCheckBox)
        let scroll = getTargetApplicationScrollOptions()
        updateSmoothDependentControl(verticalSmoothCheckBox, isOn: scroll.smoothVertical)
        updateSmoothDependentControl(horizontalSmoothCheckBox, isOn: scroll.smoothHorizontal)
    }
}
