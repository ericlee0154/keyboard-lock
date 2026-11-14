// KeyboardLock: a menu bar switch that turns the Mac's built-in keyboard off, so another
// keyboard can sit on top of it. External keyboards and the trackpad keep working.
//
// How: the built-in keyboard's HID service gets a UserKeyMapping that sends every key to
// usage 0 ("no event"). That is the same thing `hidutil property --set` does: it applies to
// that one device only, needs no permission, and is gone after a reboot.

import AppKit
import Carbon.HIToolbox
import IOKit.hid
import ServiceManagement

// Toggle hotkey: Control-Option-Command-L (pressed on the external keyboard while locked).
let hotKeyCode = UInt32(kVK_ANSI_L)
let hotKeyModifiers = UInt32(controlKey | optionKey | cmdKey)
let hotKeyLabel = "⌃⌥⌘L"

/// Whether the user wants the built-in keyboard locked; kept across quits and restarts.
let wantLockedKey = "wantLocked"

let builtInKeyboard = #"{"Built-In":true,"PrimaryUsagePage":1,"PrimaryUsage":6}"#

/// Every usage the built-in keyboard can send: the keyboard page (letters to modifiers),
/// Fn/Globe, and what the top row sends as media keys.
let lockedUsages: [UInt64] = {
    var u = (0x04...0xE7).map { 0x7_0000_0000 + UInt64($0) }
    u.append(0xFF_0000_0003)                                   // Fn / Globe
    u += [0x10, 0x04, 0x20, 0x21].map { 0xFF01_0000_0000 + UInt64($0) }  // Mission Control, Launchpad, brightness
    u += [0x221, 0xCF, 0xB3, 0xB4, 0xB5, 0xB6, 0xCD, 0xE2, 0xE9, 0xEA, 0x6F, 0x70]
        .map { 0xC_0000_0000 + UInt64($0) }                    // Spotlight, dictation, media, volume, brightness
    u.append(0x1_0000_009B)                                    // Do Not Disturb
    return u
}()

@discardableResult
func setBuiltInMapping(locked: Bool) -> Bool {
    let entries = locked
        ? lockedUsages.map {
            #"{"HIDKeyboardModifierMappingSrc":\#($0),"HIDKeyboardModifierMappingDst":\#(0x7_0000_0000 as UInt64)}"#
        }
        : []
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = ["property", "--matching", builtInKeyboard,
                   "--set", #"{"UserKeyMapping":[\#(entries.joined(separator: ","))]}"#]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

/// Names of the keyboards that are plugged in or paired and connected, other than the Mac's own.
func externalKeyboards() -> [String] {
    let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(m, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                      kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
    let devices = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? []
    return devices.compactMap { d in
        if (IOHIDDeviceGetProperty(d, kIOHIDBuiltInKey as CFString) as? Bool) == true { return nil }
        return (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "Keyboard"
    }
}

if CommandLine.arguments.contains("--list") {
    print(externalKeyboards().sorted().joined(separator: "\n"))
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let toggleItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    var locked = false
    /// Unlocked because the external keyboard went away; lock again when one is back.
    var relockWhenBack = false
    var watch: Timer?
    var hotKey: EventHotKeyRef?
    var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        // A previous run that was killed while locked would have left the keyboard dead.
        setBuiltInMapping(locked: false)

        let menu = NSMenu()
        menu.delegate = self
        toggleItem.target = self
        loginItem.target = self
        menu.addItem(toggleItem)
        let hint = NSMenuItem(title: "Hotkey: \(hotKeyLabel)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit KeyboardLock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        // Pick up where the last run left off: locked then means locked now, as soon as an
        // external keyboard is there (after a login, a Bluetooth one may take a moment).
        relockWhenBack = UserDefaults.standard.bool(forKey: wantLockedKey)
        checkKeyboards()
        refresh()

        registerHotKey()

        // A Bluetooth keyboard that runs flat or goes to sleep must not leave the Mac with no keyboard.
        watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkKeyboards() }

        // The mapping lives in the keyboard's driver; put it back if sleep dropped it.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if self?.locked == true { setBuiltInMapping(locked: true) }
        }

        // Never leave the keyboard locked behind us.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { setBuiltInMapping(locked: false); exit(0) }
            src.resume()
            signalSources.append(src)
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        setBuiltInMapping(locked: false)
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func checkKeyboards() {
        let present = !externalKeyboards().isEmpty
        if locked && !present {
            if setBuiltInMapping(locked: false) { locked = false; relockWhenBack = true }
        } else if relockWhenBack && present {
            if setBuiltInMapping(locked: true) { locked = true; relockWhenBack = false }
        } else {
            return
        }
        refresh()
    }

    @objc func toggle() {
        let want = !locked
        if relockWhenBack {
            relockWhenBack = false
        } else if want && externalKeyboards().isEmpty {
            // Locking the only keyboard would be undone at once; say no instead.
            NSSound.beep()
        } else if setBuiltInMapping(locked: want) {
            locked = want
        } else {
            NSSound.beep()
        }
        refresh()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    func refresh() {
        UserDefaults.standard.set(locked || relockWhenBack, forKey: wantLockedKey)
        let symbol = locked ? "lock.fill" : "keyboard"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: locked ? "Built-in keyboard locked" : "Built-in keyboard on")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = locked
            ? "Built-in keyboard is locked (\(hotKeyLabel) to unlock)"
            : relockWhenBack
                ? "Built-in keyboard is on until the external keyboard is back"
                : "Built-in keyboard is on (\(hotKeyLabel) to lock)"
        toggleItem.title = locked ? "Unlock Built-in Keyboard"
            : relockWhenBack ? "Stop Waiting for External Keyboard" : "Lock Built-in Keyboard"
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x4B4C_434B), id: 1)  // 'KLCK'
        RegisterEventHotKey(hotKeyCode, hotKeyModifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
