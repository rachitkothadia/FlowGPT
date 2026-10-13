import AppKit
import FlowCore

@MainActor final class ShortcutService {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onFailure: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var binding = Shortcut.fnSpace
    private var interpreter = ShortcutInterpreter()
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    func matches(_ shortcut: Shortcut) -> Bool { binding == shortcut }
    func start(_ binding: Shortcut) throws {
        stop(); guard binding.isValid else { throw FlowError.shortcut }
        self.binding = binding
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            // The run-loop source is installed exclusively on the main run loop.
            let suppress = MainActor.assumeIsolated {
                let service = Unmanaged<ShortcutService>.fromOpaque(info).takeUnretainedValue()
                return service.handle(type: type, event: event)
            }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { throw FlowError.shortcut }
        self.tap = tap; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if interpreter.release() == .release { onRelease?() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onFailure?(); return false
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, code == binding.keyCode, interpreter.held { _ = interpreter.release(); onRelease?(); return true }
        if type == .flagsChanged, interpreter.held, event.flags.rawValue & binding.modifiers != binding.modifiers {
            _ = interpreter.release(); onRelease?(); return false
        }
        if type == .keyDown, binding.matches(code: code, flags: event.flags.rawValue) {
            if interpreter.keyDown(matches: true, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) == .press { onPress?() }
            return true
        }
        return false
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil; source = nil; interpreter.reset()
    }
}
