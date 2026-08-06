import Cocoa
import ApplicationServices

// dockhide — прячет приложение (Cmd+H) при клике по его иконке в Доке,
// если оно уже является активным (frontmost). Повторный клик — показывает
// обратно штатным поведением Дока.
//
// Сборка:  swiftc -O dockhide.swift -o dockhide
// Запуск:  ./dockhide   (потребуется разрешение "Универсальный доступ")

// --- Проверка разрешения Accessibility ---
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    print("Нет разрешения Accessibility.")
    print("Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → добавьте dockhide (или терминал, из которого он запущен), затем перезапустите.")
    exit(1)
}

// --- Глобальное состояние ---
let systemWide = AXUIElementCreateSystemWide()
var eventTap: CFMachPort? = nil
var swallowNextMouseUp = false

// Возвращает приложение, если под точкой point находится его иконка в Доке
func appUnderDockIcon(at point: CGPoint) -> NSRunningApplication? {
    var elRef: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide,
                                           Float(point.x), Float(point.y),
                                           &elRef) == .success,
          let el = elRef else { return nil }

    // Элемент должен принадлежать процессу Dock
    var pid: pid_t = 0
    guard AXUIElementGetPid(el, &pid) == .success,
          let owner = NSRunningApplication(processIdentifier: pid),
          owner.bundleIdentifier == "com.apple.dock" else { return nil }

    // И быть именно иконкой приложения (не папкой, не корзиной, не разделителем)
    var subroleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef)
    guard (subroleRef as? String) == "AXApplicationDockItem" else { return nil }

    // Приложение должно быть запущено
    var runningRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, "AXIsApplicationRunning" as CFString, &runningRef)
    guard (runningRef as? NSNumber)?.boolValue == true else { return nil }

    // URL бандла иконки → сопоставляем с запущенными приложениями
    var urlRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlRef)
    guard let nsurl = urlRef as? NSURL else { return nil }
    let iconURL = (nsurl as URL).standardizedFileURL

    return NSWorkspace.shared.runningApplications.first {
        $0.bundleURL?.standardizedFileURL == iconURL
    }
}

// --- Callback для event tap ---
func tapCallback(proxy: CGEventTapProxy,
                 type: CGEventType,
                 event: CGEvent,
                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // Система могла отключить tap — включаем обратно
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }

    case .leftMouseUp:
        if swallowNextMouseUp {
            swallowNextMouseUp = false
            return nil
        }

    case .leftMouseDown:
        // Клики с модификаторами не трогаем (Ctrl — контекстное меню,
        // Option/Cmd — штатные жесты Дока)
        guard event.flags.intersection([.maskCommand, .maskAlternate,
                                        .maskControl, .maskShift]).isEmpty
        else { break }

        if let app = appUnderDockIcon(at: event.location),
           app.isActive, !app.isHidden {
            app.hide()
            swallowNextMouseUp = true
            return nil  // не отдаём клик Доку, иначе он тут же активирует приложение
        }

    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

// --- Создание event tap ---
let mask: CGEventMask =
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.leftMouseUp.rawValue)

eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                             place: .headInsertEventTap,
                             options: .defaultTap,
                             eventsOfInterest: mask,
                             callback: tapCallback,
                             userInfo: nil)

guard let tap = eventTap else {
    print("Не удалось создать event tap — проверьте разрешение Accessibility.")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("dockhide запущен: клик по иконке активного приложения в Доке прячет его.")
CFRunLoopRun()
