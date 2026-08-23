//
//  VirtualDisplaySession.swift
//  Light Stats
//
//  Runtime-resolved CoreGraphics virtual display (CGVirtualDisplay*).
//  Holding the object registers a display with WindowServer, which is what
//  lets a plugged-in MacBook stay in closed-clamshell without a physical HDMI
//  dummy. Classes are looked up by name so a missing OS still boots the app.
//

import CoreGraphics
import Foundation
import ObjectiveC

/// One retained virtual display. Shape C helper: start() creates, stop() drops
/// the object (WindowServer removes the display). Main-actor only.
@MainActor
final class VirtualDisplaySession {

    private(set) var displayID: CGDirectDisplayID?
    private var display: AnyObject?

    var isActive: Bool { display != nil }

    static var isSupported: Bool {
        NSClassFromString("CGVirtualDisplay") != nil
            && NSClassFromString("CGVirtualDisplayDescriptor") != nil
            && NSClassFromString("CGVirtualDisplaySettings") != nil
            && NSClassFromString("CGVirtualDisplayMode") != nil
    }

    /// True when some non-built-in display other than `excluding` is online.
    static func hasForeignExternalDisplay(excluding excludedID: CGDirectDisplayID?) -> Bool {
        for id in onlineDisplayIDs() where CGDisplayIsBuiltin(id) == 0 {
            if let excludedID, id == excludedID { continue }
            return true
        }
        return false
    }

    @discardableResult
    func start() -> Bool {
        if isActive { return true }
        guard Self.isSupported else { return false }
        guard let created = makeDisplay() else { return false }
        display = created.object
        displayID = created.displayID
        activateIfNeeded(created.displayID)
        placeBesideMain(created.displayID)
        return true
    }

    func stop() {
        display = nil
        displayID = nil
    }

    // MARK: - Create

    private struct CreatedDisplay {
        let object: AnyObject
        let displayID: CGDirectDisplayID
    }

    private func makeDisplay() -> CreatedDisplay? {
        guard
            let descClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
            let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
            let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
            let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type
        else { return nil }

        let desc = descClass.init()
        ObjCCall.setUInt32(desc, "setVendorID:", Self.vendorID)
        ObjCCall.setUInt32(desc, "setProductID:", Self.productID)
        ObjCCall.setUInt32(desc, "setSerialNum:", 1)
        ObjCCall.setObject(desc, "setName:", "Light Stats" as NSString)
        ObjCCall.setUInt32(desc, "setMaxPixelsWide:", Self.pixelWidth)
        ObjCCall.setUInt32(desc, "setMaxPixelsHigh:", Self.pixelHeight)
        ObjCCall.setSize(desc, "setSizeInMillimeters:", CGSize(width: 331, height: 186))
        ObjCCall.setObject(desc, "setQueue:", DispatchQueue.main)

        guard let display = ObjCCall.initWithDescriptor(displayClass, descriptor: desc) else { return nil }
        guard let mode = ObjCCall.initMode(
            modeClass,
            width: Self.pixelWidth,
            height: Self.pixelHeight,
            refreshRate: 60
        ) else { return nil }

        let settings = settingsClass.init()
        ObjCCall.setUInt32(settings, "setHiDPI:", 1)
        ObjCCall.setObject(settings, "setModes:", [mode] as NSArray)
        guard ObjCCall.applySettings(display, settings) else { return nil }

        let id = ObjCCall.displayID(display)
        guard id != 0 else { return nil }
        return CreatedDisplay(object: display, displayID: id)
    }

    // MARK: - Topology

    private func activateIfNeeded(_ id: CGDirectDisplayID) {
        if Self.activeDisplayIDs().contains(id) { return }
        guard let managerClass = NSClassFromString("SLWindowMirroringManager") else { return }
        let shared = ObjCCall.classObject(managerClass, "sharedManager")
            ?? ObjCCall.classObject(managerClass, "shared")
        guard let shared else { return }
        _ = ObjCCall.extend(shared, displayID: id)
    }

    private func placeBesideMain(_ id: CGDirectDisplayID) {
        let main = CGMainDisplayID()
        guard id != main else { return }
        let originX = Int32(CGDisplayBounds(main).maxX.rounded())
        let originY = Int32(CGDisplayBounds(main).minY.rounded())
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        if CGConfigureDisplayOrigin(config, id, originX, originY) == .success {
            _ = CGCompleteDisplayConfiguration(config, .forSession)
        } else {
            CGCancelDisplayConfiguration(config)
        }
    }

    // MARK: - Display lists

    static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        displayIDs(CGGetOnlineDisplayList)
    }

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        displayIDs(CGGetActiveDisplayList)
    }

    private static func displayIDs(
        _ getter: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>) -> CGError
    ) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard getter(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        guard getter(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static let vendorID: UInt32 = 0x4C53
    private static let productID: UInt32 = 0x4B41
    private static let pixelWidth: UInt32 = 1920
    private static let pixelHeight: UInt32 = 1080
}

// MARK: - objc_msgSend helpers

private enum ObjCCall {
    static func setUInt32(_ object: AnyObject, _ selectorName: String, _ value: UInt32) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return }
        typealias MsgSend = @convention(c) (AnyObject, Selector, UInt32) -> Void
        let impl = class_getMethodImplementation(object_getClass(object), selector)
        unsafeBitCast(impl, to: MsgSend.self)(object, selector, value)
    }

    static func setObject(_ object: AnyObject, _ selectorName: String, _ value: AnyObject) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return }
        typealias MsgSend = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let impl = class_getMethodImplementation(object_getClass(object), selector)
        unsafeBitCast(impl, to: MsgSend.self)(object, selector, value)
    }

    static func setSize(_ object: AnyObject, _ selectorName: String, _ value: CGSize) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return }
        typealias MsgSend = @convention(c) (AnyObject, Selector, CGSize) -> Void
        let impl = class_getMethodImplementation(object_getClass(object), selector)
        unsafeBitCast(impl, to: MsgSend.self)(object, selector, value)
    }

    static func initWithDescriptor(_ displayClass: NSObject.Type, descriptor: AnyObject) -> AnyObject? {
        let allocSelector = NSSelectorFromString("alloc")
        guard let allocated = (displayClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() else {
            return nil
        }
        let selector = NSSelectorFromString("initWithDescriptor:")
        guard allocated.responds(to: selector) else { return nil }
        typealias MsgSend = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
        let impl = class_getMethodImplementation(object_getClass(allocated), selector)
        return unsafeBitCast(impl, to: MsgSend.self)(allocated, selector, descriptor)?.takeRetainedValue()
    }

    static func initMode(
        _ modeClass: NSObject.Type,
        width: UInt32,
        height: UInt32,
        refreshRate: Double
    ) -> AnyObject? {
        let allocSelector = NSSelectorFromString("alloc")
        guard let allocated = (modeClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() else {
            return nil
        }
        let selector = NSSelectorFromString("initWithWidth:height:refreshRate:")
        guard allocated.responds(to: selector) else { return nil }
        typealias MsgSend = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> Unmanaged<AnyObject>?
        let impl = class_getMethodImplementation(object_getClass(allocated), selector)
        return unsafeBitCast(impl, to: MsgSend.self)(allocated, selector, width, height, refreshRate)?
            .takeRetainedValue()
    }

    static func applySettings(_ display: AnyObject, _ settings: AnyObject) -> Bool {
        let selector = NSSelectorFromString("applySettings:")
        guard display.responds(to: selector) else { return false }
        typealias MsgSend = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let impl = class_getMethodImplementation(object_getClass(display), selector)
        return unsafeBitCast(impl, to: MsgSend.self)(display, selector, settings)
    }

    static func displayID(_ display: AnyObject) -> CGDirectDisplayID {
        let selector = NSSelectorFromString("displayID")
        guard display.responds(to: selector) else { return 0 }
        typealias MsgSend = @convention(c) (AnyObject, Selector) -> UInt32
        let impl = class_getMethodImplementation(object_getClass(display), selector)
        return unsafeBitCast(impl, to: MsgSend.self)(display, selector)
    }

    static func classObject(_ cls: AnyClass, _ selectorName: String) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard cls.responds(to: selector) else { return nil }
        return (cls as AnyObject).perform(selector)?.takeUnretainedValue()
    }

    static func extend(_ manager: AnyObject, displayID: CGDirectDisplayID) -> Bool {
        let selector = NSSelectorFromString("extend:")
        guard manager.responds(to: selector) else { return false }
        typealias MsgSend = @convention(c) (AnyObject, Selector, UInt32) -> Bool
        let impl = class_getMethodImplementation(object_getClass(manager), selector)
        return unsafeBitCast(impl, to: MsgSend.self)(manager, selector, displayID)
    }
}
