import Cocoa
import IOKit
import IOKit.graphics

private enum SafetyPolicy {
    static let lowBatteryCutoff = 10
}

private enum AppLanguage: String {
    case chinese
    case english
}

private final class Localization {
    static let shared = Localization()

    private let defaultsKey = "preferred-language"
    private(set) var language: AppLanguage

    private init() {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey),
           let language = AppLanguage(rawValue: saved) {
            self.language = language
        } else {
            self.language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }

    func toggle() {
        language = language == .chinese ? .english : .chinese
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
    }
}

private func tr(_ chinese: String, _ english: String) -> String {
    Localization.shared.text(chinese, english)
}

private final class DisplayBrightnessManager {
    static let shared = DisplayBrightnessManager()

    private let defaultsKey = "saved-built-in-display-brightness"
    private var savedBrightness: Float?

    private init() {}

    /// Restores brightness left behind if the previous app process ended
    /// before its normal cleanup path could run.
    func recoverFromInterruptedSession() {
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else { return }
        let saved = Float(UserDefaults.standard.double(forKey: defaultsKey))
        if setBuiltInBrightness(saved) {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    func dimForSession() {
        guard savedBrightness == nil,
              let current = builtInBrightness() else { return }
        savedBrightness = current
        UserDefaults.standard.set(Double(current), forKey: defaultsKey)
        _ = setBuiltInBrightness(0)
    }

    func restoreAfterSession() {
        let persisted = UserDefaults.standard.object(forKey: defaultsKey).map { _ in
            Float(UserDefaults.standard.double(forKey: defaultsKey))
        }
        guard let brightness = savedBrightness ?? persisted else { return }
        if setBuiltInBrightness(brightness) {
            savedBrightness = nil
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    private func builtInBrightness() -> Float? {
        guard let service = builtInDisplayService() else { return nil }
        defer { IOObjectRelease(service) }
        var value: Float = 0
        guard IODisplayGetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            &value
        ) == kIOReturnSuccess else {
            return nil
        }
        return value
    }

    @discardableResult
    private func setBuiltInBrightness(_ value: Float) -> Bool {
        guard let service = builtInDisplayService() else { return false }
        defer { IOObjectRelease(service) }
        return IODisplaySetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            max(0, min(1, value))
        ) == kIOReturnSuccess
    }

    /// Maps Core Graphics' built-in display to its IOKit display service so
    /// external monitors are never modified.
    private func builtInDisplayService() -> io_service_t? {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else { return nil }

        var displayIDs = Array(repeating: CGDirectDisplayID(0), count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success,
              let displayID = displayIDs.prefix(Int(displayCount)).first(where: {
                  CGDisplayIsBuiltin($0) != 0
              }) else { return nil }

        let expectedVendor = UInt32(CGDisplayVendorNumber(displayID))
        let expectedProduct = UInt32(CGDisplayModelNumber(displayID))
        let expectedSerial = UInt32(CGDisplaySerialNumber(displayID))

        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IODisplayConnect"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }

            let info = IODisplayCreateInfoDictionary(
                service,
                UInt32(kIODisplayOnlyPreferredName)
            ).takeRetainedValue() as NSDictionary
            let vendor = (info[kDisplayVendorID] as? NSNumber)?.uint32Value
            let product = (info[kDisplayProductID] as? NSNumber)?.uint32Value
            let serial = (info[kDisplaySerialNumber] as? NSNumber)?.uint32Value ?? 0

            let serialMatches = expectedSerial == 0 || serial == expectedSerial
            if vendor == expectedVendor, product == expectedProduct, serialMatches {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }
}

private struct PowerSnapshot {
    let sleepDisabled: Bool
    let onACPower: Bool
    let batteryPercent: Int?
    let charging: Bool
}

private enum PowerToolError: LocalizedError {
    case alreadyRunning
    case markerCreationFailed(String)
    case launchFailed(String)
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return tr("合盖工作会话已在运行。", "A clamshell work session is already running.")
        case .markerCreationFailed(let message):
            return tr("无法创建安全会话标记：\(message)", "Could not create the secure session marker: \(message)")
        case .launchFailed(let message):
            return tr("无法启动系统电源命令：\(message)", "Could not start the system power command: \(message)")
        case .authorizationFailed(let message):
            return message
        }
    }
}

private final class PowerManager {
    static let shared = PowerManager()

    private let workQueue = DispatchQueue(label: "com.codex.keepawake.power", qos: .userInitiated)
    private let monitorQueue = DispatchQueue(label: "com.codex.keepawake.monitor", qos: .utility)
    private let fileManager = FileManager.default
    private var monitorProcess: Process?
    private var monitorToken: String?

    private lazy var supportDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("KeepCodexAwake", isDirectory: true)
    }()

    private lazy var markerURL: URL = {
        supportDirectory.appendingPathComponent("active-session", isDirectory: false)
    }()

    private init() {
        // A hard-killed previous app cannot remove its user-owned marker, even
        // though the privileged monitor still restores SleepDisabled. A fresh
        // launch can safely discard that stale marker before starting a session.
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let staleMarker = base
            .appendingPathComponent("KeepCodexAwake", isDirectory: true)
            .appendingPathComponent("active-session", isDirectory: false)
        try? fileManager.removeItem(at: staleMarker)
    }

    var hasManagedSession: Bool {
        monitorProcess?.isRunning == true
    }

    func readSnapshot() -> PowerSnapshot {
        let ioreg = Self.run("/usr/sbin/ioreg", ["-r", "-k", "SleepDisabled", "-d", "4"])
        let disabled = ioreg.output.contains("\"SleepDisabled\" = Yes") ||
            ioreg.output.contains("\"SleepDisabled\" = 1")

        let battery = Self.run("/usr/bin/pmset", ["-g", "batt"]).output
        let onAC = battery.contains("'AC Power'")
        let charging = battery.localizedCaseInsensitiveContains("charging") &&
            !battery.localizedCaseInsensitiveContains("discharging")
        let percent = Self.firstBatteryPercentage(in: battery)

        return PowerSnapshot(
            sleepDisabled: disabled,
            onACPower: onAC,
            batteryPercent: percent,
            charging: charging
        )
    }

    func readSnapshotAsync(_ completion: @escaping (PowerSnapshot) -> Void) {
        workQueue.async {
            let snapshot = self.readSnapshot()
            DispatchQueue.main.async {
                completion(snapshot)
            }
        }
    }

    /// Starts one privileged shell that owns the sleep override for the session.
    /// The shell restores normal sleep when the app exits, the marker disappears,
    /// or battery power falls to the configured safety cutoff.
    func startManagedSession(onEnded: @escaping (Error?) -> Void) throws {
        guard monitorProcess?.isRunning != true else {
            throw PowerToolError.alreadyRunning
        }

        let token = UUID().uuidString
        do {
            try fileManager.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try (token + "\n").write(to: markerURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
        } catch {
            throw PowerToolError.markerCreationFailed(error.localizedDescription)
        }

        let appPID = ProcessInfo.processInfo.processIdentifier
        let quotedMarker = Self.shellQuote(markerURL.path)
        let quotedToken = Self.shellQuote(token)
        let rootScript = """
        set -u
        /usr/bin/pmset -a disablesleep 1
        cleanup() {
          /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true
        }
        trap cleanup EXIT HUP INT TERM

        while /bin/kill -0 \(appPID) >/dev/null 2>&1; do
          if ! /usr/bin/grep -Fqx -- \(quotedToken) \(quotedMarker) >/dev/null 2>&1; then
            break
          fi

          battery_status=$(/usr/bin/pmset -g batt 2>/dev/null || true)
          case "$battery_status" in
            *"Battery Power"*)
              battery_percent=$(printf '%s\n' "$battery_status" | /usr/bin/awk 'match($0, /[0-9][0-9]*%/) { print substr($0, RSTART, RLENGTH - 1); exit }')
              if [ -n "$battery_percent" ] && [ "$battery_percent" -le \(SafetyPolicy.lowBatteryCutoff) ]; then
                break
              fi
              ;;
          esac

          /bin/sleep 3
        done
        """

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", Self.authorizedAppleScript(for: rootScript, timeout: 604_800)]
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            removeMarker(ifMatching: token)
            throw PowerToolError.launchFailed(error.localizedDescription)
        }

        monitorProcess = process
        monitorToken = token

        monitorQueue.async { [weak self, weak process] in
            guard let process else { return }
            process.waitUntilExit()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            let exitStatus = process.terminationStatus

            DispatchQueue.main.async {
                guard let self else { return }
                self.removeMarker(ifMatching: token)
                if self.monitorProcess === process {
                    self.monitorProcess = nil
                    self.monitorToken = nil
                }

                if exitStatus == 0 {
                    onEnded(nil)
                } else {
                    let friendly = Self.friendlyAuthorizationError(errorText)
                    onEnded(PowerToolError.authorizationFailed(friendly))
                }
            }
        }
    }

    /// Ends the root monitor by invalidating its unprivileged marker. If the
    /// current override came from another process, request a one-shot admin
    /// authorization so the button can still recover the Mac.
    func stopSession(completion: @escaping (Result<Void, Error>) -> Void) {
        if monitorProcess?.isRunning == true, let token = monitorToken {
            removeMarker(ifMatching: token)
            waitUntilSleepIsEnabled(attemptsRemaining: 32, completion: completion)
            return
        }

        runAuthorizedOneShot("/usr/bin/pmset -a disablesleep 0", completion: completion)
    }

    func invalidateManagedSession() {
        guard let token = monitorToken else { return }
        removeMarker(ifMatching: token)
    }

    private func waitUntilSleepIsEnabled(
        attemptsRemaining: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        workQueue.asyncAfter(deadline: .now() + 0.25) {
            let isStillDisabled = self.readSnapshot().sleepDisabled
            DispatchQueue.main.async {
                if !isStillDisabled {
                    completion(.success(()))
                } else if attemptsRemaining > 1 {
                    self.waitUntilSleepIsEnabled(
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                } else {
                    completion(.failure(PowerToolError.authorizationFailed(
                        tr(
                            "系统尚未恢复正常睡眠，请再点一次关闭。",
                            "Normal sleep has not been restored yet. Please click Disable once more."
                        )
                    )))
                }
            }
        }
    }

    private func runAuthorizedOneShot(
        _ shellCommand: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        workQueue.async {
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", Self.authorizedAppleScript(for: shellCommand, timeout: 120)]
            process.standardOutput = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(()))
                    } else {
                        completion(.failure(PowerToolError.authorizationFailed(
                            Self.friendlyAuthorizationError(text)
                        )))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(PowerToolError.launchFailed(error.localizedDescription)))
                }
            }
        }
    }

    private func removeMarker(ifMatching token: String) {
        guard let current = try? String(contentsOf: markerURL, encoding: .utf8),
              current.trimmingCharacters(in: .whitespacesAndNewlines) == token else {
            return
        }
        try? fileManager.removeItem(at: markerURL)
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, "")
        }
    }

    private static func firstBatteryPercentage(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3})%"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func authorizedAppleScript(for shellScript: String, timeout: Int) -> String {
        let encoded = Data(shellScript.utf8).base64EncodedString()
        let command = "/bin/echo \(encoded) | /usr/bin/base64 -D | /bin/sh"
        return "with timeout of \(timeout) seconds\n" +
            "do shell script \"\(command)\" with administrator privileges\n" +
            "end timeout"
    }

    private static func friendlyAuthorizationError(_ rawText: String) -> String {
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains("User canceled") || cleaned.contains("-128") {
            return tr(
                "已取消管理员授权，系统设置没有改变。",
                "Administrator authorization was cancelled. No system setting was changed."
            )
        }
        if cleaned.isEmpty {
            return tr("系统拒绝了电源设置更改。", "macOS rejected the power setting change.")
        }
        return tr(
            "无法更改系统睡眠设置：\(cleaned)",
            "Could not change the system sleep setting: \(cleaned)"
        )
    }
}

private final class StatusDotView: NSView {
    var color: NSColor = .systemGray {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 12, height: 12) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
    }
}

private final class PrimaryButton: NSButton {
    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = 12
        layer?.backgroundColor = (isEnabled ? NSColor.controlAccentColor : NSColor.disabledControlTextColor)
            .withAlphaComponent(isEnabled ? 1 : 0.35)
            .cgColor
    }

    func setTitle(_ text: String) {
        attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
            ]
        )
        setAccessibilityLabel(text)
    }
}

private final class DashboardViewController: NSViewController {
    var onStateChanged: ((PowerSnapshot) -> Void)?
    var onReadyToTerminate: (() -> Void)?
    var onLanguageChanged: (() -> Void)?

    private let manager = PowerManager.shared
    private let statusDot = StatusDotView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let headlineLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let explanationLabel = NSTextField(wrappingLabelWithString: "")
    private let powerLabel = NSTextField(labelWithString: "")
    private let actionButton = PrimaryButton(title: "", target: nil, action: nil)
    private let languageButton = NSButton(title: "", target: nil, action: nil)
    private let footnoteLabel = NSTextField(wrappingLabelWithString: "")

    private var timer: Timer?
    private var pollInFlight = false
    private var busyAction: BusyAction?
    private var lastSnapshot: PowerSnapshot?
    private var temporaryMessage: TemporaryMessage?

    private enum BusyAction {
        case enabling
        case disabling
    }

    private enum TemporaryMessage {
        case restored
        case lowBattery
    }

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        view = effect

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: "laptopcomputer.and.arrow.down",
            accessibilityDescription: tr("笔记本电脑合盖工作", "Keep working with the MacBook lid closed")
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        headlineLabel.font = .systemFont(ofSize: 27, weight: .bold)
        headlineLabel.alignment = .center
        headlineLabel.textColor = .labelColor

        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2

        let titleStack = NSStackView(views: [icon, headlineLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .centerX
        titleStack.spacing = 8

        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        let statusRow = NSStackView(views: [statusDot, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 7

        explanationLabel.font = .systemFont(ofSize: 13)
        explanationLabel.textColor = .secondaryLabelColor
        explanationLabel.maximumNumberOfLines = 2

        powerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        powerLabel.textColor = .tertiaryLabelColor

        let statusStack = NSStackView(views: [statusRow, explanationLabel, powerLabel])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 7
        statusStack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)

        let card = NSBox()
        card.boxType = .custom
        card.fillColor = .controlBackgroundColor
        card.borderColor = .separatorColor
        card.borderWidth = 1
        card.cornerRadius = 13
        card.contentView = statusStack

        actionButton.target = self
        actionButton.action = #selector(toggleMode)
        actionButton.isBordered = false
        actionButton.wantsLayer = true
        actionButton.setButtonType(.momentaryChange)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        languageButton.target = self
        languageButton.action = #selector(toggleLanguage)
        languageButton.bezelStyle = .roundRect
        languageButton.controlSize = .small
        languageButton.font = .systemFont(ofSize: 12, weight: .medium)
        languageButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(languageButton)

        footnoteLabel.font = .systemFont(ofSize: 11.5)
        footnoteLabel.textColor = .tertiaryLabelColor
        footnoteLabel.alignment = .center
        footnoteLabel.maximumNumberOfLines = 3

        let mainStack = NSStackView(views: [titleStack, card, actionButton, footnoteLabel])
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 20
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),
            subtitleLabel.widthAnchor.constraint(equalToConstant: 400),
            card.widthAnchor.constraint(equalToConstant: 420),
            card.heightAnchor.constraint(equalToConstant: 112),
            actionButton.widthAnchor.constraint(equalToConstant: 420),
            actionButton.heightAnchor.constraint(equalToConstant: 52),
            footnoteLabel.widthAnchor.constraint(equalToConstant: 410),
            mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30),
            mainStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mainStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            languageButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            languageButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            languageButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 62)
        ])

        applyLocalization()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    func startPolling() {
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func performToggleFromMenu() {
        toggleMode()
    }

    func prepareToTerminate() {
        let current = manager.readSnapshot()
        guard current.sleepDisabled else {
            onReadyToTerminate?()
            return
        }

        busyAction = .disabling
        updateUI(with: current)
        manager.stopSession { [weak self] result in
            guard let self else { return }
            self.busyAction = nil
            switch result {
            case .success:
                DisplayBrightnessManager.shared.restoreAfterSession()
                self.onReadyToTerminate?()
            case .failure(let error):
                self.showError(error.localizedDescription)
                NSApp.reply(toApplicationShouldTerminate: false)
                self.refresh()
            }
        }
    }

    private func refresh() {
        guard !pollInFlight else { return }
        pollInFlight = true
        manager.readSnapshotAsync { [weak self] snapshot in
            guard let self else { return }
            self.pollInFlight = false

            if self.busyAction == .enabling, snapshot.sleepDisabled {
                DisplayBrightnessManager.shared.dimForSession()
                self.busyAction = nil
                self.temporaryMessage = nil
            } else if self.busyAction == .disabling, !snapshot.sleepDisabled {
                DisplayBrightnessManager.shared.restoreAfterSession()
                self.busyAction = nil
                self.temporaryMessage = nil
            }

            if self.lastSnapshot?.sleepDisabled == true,
               !snapshot.sleepDisabled,
               snapshot.onACPower == false,
               let percent = snapshot.batteryPercent,
               percent <= SafetyPolicy.lowBatteryCutoff {
                DisplayBrightnessManager.shared.restoreAfterSession()
                self.temporaryMessage = .lowBattery
            }

            self.lastSnapshot = snapshot
            self.updateUI(with: snapshot)
            self.onStateChanged?(snapshot)
        }
    }

    @objc private func toggleMode() {
        guard busyAction == nil else { return }
        let snapshot = manager.readSnapshot()

        if snapshot.sleepDisabled {
            busyAction = .disabling
            temporaryMessage = nil
            updateUI(with: snapshot)
            manager.stopSession { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    DisplayBrightnessManager.shared.restoreAfterSession()
                    self.temporaryMessage = .restored
                case .failure(let error):
                    self.busyAction = nil
                    self.showError(error.localizedDescription)
                }
                self.refresh()
            }
            return
        }

        if !confirmSafety(snapshot: snapshot) {
            return
        }

        busyAction = .enabling
        temporaryMessage = nil
        updateUI(with: snapshot)
        do {
            try manager.startManagedSession { [weak self] error in
                guard let self else { return }
                if let error, self.busyAction == .enabling {
                    self.busyAction = nil
                    self.showError(error.localizedDescription)
                }
                self.refresh()
            }
        } catch {
            busyAction = nil
            showError(error.localizedDescription)
            refresh()
        }
    }

    private func confirmSafety(snapshot: PowerSnapshot) -> Bool {
        if !snapshot.onACPower,
           let percent = snapshot.batteryPercent,
           percent <= SafetyPolicy.lowBatteryCutoff {
            showError(tr(
                "当前电量只有 \(percent)%，请先接上电源再开启。",
                "Battery is at \(percent)%. Connect power before enabling this mode."
            ))
            return false
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("开启合盖工作模式？", "Enable clamshell work mode?")
        alert.informativeText = tr(
            "开启后，合上屏幕不会再让 Mac 睡眠。请保持通风，最好接上电源，不要把运行中的电脑放进包里。",
            "With this mode enabled, closing the lid will no longer put your Mac to sleep. Keep it ventilated, preferably connected to power, and never place it in a bag while running."
        )
        alert.addButton(withTitle: tr("开启", "Enable"))
        alert.addButton(withTitle: tr("取消", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func toggleLanguage() {
        Localization.shared.toggle()
        applyLocalization()
        if let snapshot = lastSnapshot {
            updateUI(with: snapshot)
        }
        onLanguageChanged?()
    }

    private func applyLocalization() {
        headlineLabel.stringValue = tr("合盖工作", "Clamshell Awake")
        subtitleLabel.stringValue = tr(
            "合上 Mac 屏幕后，让 Codex 和其他后台任务继续运行。",
            "Keep Codex and other background tasks running after you close your Mac."
        )
        footnoteLabel.stringValue = tr(
            "开启后内置屏幕亮度降至最低；关闭、退出或电量降至 \(SafetyPolicy.lowBatteryCutoff)% 时自动恢复。",
            "Built-in display brightness drops to minimum; it is restored on disable, exit, or at \(SafetyPolicy.lowBatteryCutoff)% battery."
        )
        languageButton.title = Localization.shared.language == .chinese ? "EN" : "中文"
        languageButton.toolTip = tr("切换到英文", "Switch to Chinese")
        languageButton.setAccessibilityLabel(languageButton.toolTip)
    }

    private func updateUI(with snapshot: PowerSnapshot) {
        actionButton.isEnabled = busyAction == nil

        switch busyAction {
        case .enabling:
            statusDot.color = .systemOrange
            statusLabel.stringValue = tr("等待管理员授权…", "Waiting for administrator approval…")
            explanationLabel.stringValue = tr(
                "请在系统弹窗中输入 Mac 密码。",
                "Enter your Mac password in the system dialog."
            )
            actionButton.setTitle(tr("正在开启…", "Enabling…"))
        case .disabling:
            statusDot.color = .systemOrange
            statusLabel.stringValue = tr("正在恢复正常睡眠…", "Restoring normal sleep…")
            explanationLabel.stringValue = tr(
                "安全会话正在收尾，通常只需几秒。",
                "The safety session is ending. This usually takes a few seconds."
            )
            actionButton.setTitle(tr("正在关闭…", "Disabling…"))
        case nil:
            if snapshot.sleepDisabled {
                statusDot.color = .systemGreen
                statusLabel.stringValue = tr("已开启 · 合盖后继续工作", "Enabled · Work continues with lid closed")
                explanationLabel.stringValue = tr(
                    "Codex 和后台任务会继续运行。完成后请点击下方按钮关闭。",
                    "Codex and background tasks will keep running. Disable the mode when finished."
                )
                actionButton.setTitle(tr("关闭并恢复正常睡眠", "Disable and restore normal sleep"))
            } else {
                statusDot.color = .systemGray
                statusLabel.stringValue = tr("已关闭 · 系统正常睡眠", "Disabled · Normal system sleep")
                switch temporaryMessage {
                case .restored:
                    explanationLabel.stringValue = tr(
                        "已恢复 Mac 的正常合盖睡眠。",
                        "Normal Mac sleep on lid close has been restored."
                    )
                case .lowBattery:
                    explanationLabel.stringValue = tr(
                        "电量已降至 \(SafetyPolicy.lowBatteryCutoff)%，已自动恢复正常睡眠。",
                        "Battery reached \(SafetyPolicy.lowBatteryCutoff)%. Normal sleep was restored automatically."
                    )
                case nil:
                    explanationLabel.stringValue = tr(
                        "合上屏幕后，Mac 会按系统默认行为睡眠。",
                        "Your Mac will follow its normal sleep behavior when the lid is closed."
                    )
                }
                actionButton.setTitle(tr("开启合盖工作模式", "Enable clamshell work mode"))
            }
        }

        let powerSource = snapshot.onACPower
            ? tr("已接电源", "Power adapter")
            : tr("正在使用电池", "On battery")
        let battery = snapshot.batteryPercent.map {
            tr("  ·  电量 \($0)%", "  ·  Battery \($0)%")
        } ?? ""
        let charging = snapshot.charging ? tr("  ·  充电中", "  ·  Charging") : ""
        powerLabel.stringValue = powerSource + battery + charging
        actionButton.needsDisplay = true
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("操作没有完成", "The operation did not complete")
        alert.informativeText = message
        alert.addButton(withTitle: tr("好", "OK"))
        alert.runModal()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSWindow!
    private var dashboard: DashboardViewController!
    private var statusItem: NSStatusItem!
    private var statusTitleItem: NSMenuItem!
    private var showMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var quitMenuItem: NSMenuItem!
    private var lastSnapshot = PowerSnapshot(
        sleepDisabled: false,
        onACPower: false,
        batteryPercent: nil,
        charging: false
    )
    private var terminationIsApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DisplayBrightnessManager.shared.recoverFromInterruptedSession()
        NSApp.setActivationPolicy(.accessory)
        buildWindow()
        buildStatusItem()
        showWindow()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // Clicking the desktop app again must recover a window hidden with the
        // red close button. The keep-awake session itself may still be active.
        showWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationIsApproved || !PowerManager.shared.readSnapshot().sleepDisabled {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("先恢复正常睡眠再退出？", "Restore normal sleep before quitting?")
        alert.informativeText = tr(
            "为了避免忘记关闭合盖模式，退出前会先恢复 Mac 的默认睡眠行为和原始屏幕亮度。",
            "Before quitting, the app will restore normal Mac sleep behavior and the original display brightness."
        )
        alert.addButton(withTitle: tr("恢复并退出", "Restore and Quit"))
        alert.addButton(withTitle: tr("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        dashboard.onReadyToTerminate = { [weak self] in
            guard let self else { return }
            self.terminationIsApproved = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        dashboard.prepareToTerminate()
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        PowerManager.shared.invalidateManagedSession()
        DisplayBrightnessManager.shared.restoreAfterSession()
    }

    func menuWillOpen(_ menu: NSMenu) {
        syncMenu(with: PowerManager.shared.readSnapshot())
    }

    private func buildWindow() {
        dashboard = DashboardViewController()
        dashboard.onStateChanged = { [weak self] snapshot in
            self?.lastSnapshot = snapshot
            self?.syncStatusIcon(with: snapshot)
        }
        dashboard.onLanguageChanged = { [weak self] in
            self?.applyLocalization()
        }

        window = NSWindow(contentViewController: dashboard)
        window.title = tr("合盖工作", "Clamshell Awake")
        window.setContentSize(NSSize(width: 500, height: 500))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = tr("合盖工作", "Clamshell Awake")

        let menu = NSMenu()
        menu.delegate = self
        statusTitleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusTitleItem.isEnabled = false
        menu.addItem(statusTitleItem)
        menu.addItem(.separator())
        showMenuItem = menu.addItem(withTitle: "", action: #selector(showWindow), keyEquivalent: "o")
        showMenuItem.target = self
        toggleMenuItem = menu.addItem(withTitle: "", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(.separator())
        quitMenuItem = menu.addItem(withTitle: "", action: #selector(quitApp), keyEquivalent: "q")
        quitMenuItem.target = self
        statusItem.menu = menu
        applyLocalization()
        syncStatusIcon(with: lastSnapshot)
    }

    private func syncStatusIcon(with snapshot: PowerSnapshot) {
        let symbol = snapshot.sleepDisabled ? "bolt.horizontal.circle.fill" : "moon.zzz"
        let description = snapshot.sleepDisabled
            ? tr("合盖工作已开启", "Clamshell work mode is enabled")
            : tr("合盖工作已关闭", "Clamshell work mode is disabled")
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        statusItem.button?.contentTintColor = snapshot.sleepDisabled ? .systemGreen : .labelColor
        statusItem.button?.toolTip = description
        syncMenu(with: snapshot)
    }

    private func syncMenu(with snapshot: PowerSnapshot) {
        statusTitleItem?.title = snapshot.sleepDisabled
            ? tr("合盖工作：已开启", "Clamshell Awake: Enabled")
            : tr("合盖工作：已关闭", "Clamshell Awake: Disabled")
        toggleMenuItem?.title = snapshot.sleepDisabled
            ? tr("关闭并恢复休眠", "Disable and restore sleep")
            : tr("开启合盖工作", "Enable clamshell work")
    }

    private func applyLocalization() {
        window?.title = tr("合盖工作", "Clamshell Awake")
        showMenuItem?.title = tr("显示控制面板", "Show control panel")
        quitMenuItem?.title = tr("退出", "Quit")
        syncStatusIcon(with: lastSnapshot)
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboard.startPolling()
    }

    @objc private func toggleFromMenu() {
        showWindow()
        dashboard.performToggleFromMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
