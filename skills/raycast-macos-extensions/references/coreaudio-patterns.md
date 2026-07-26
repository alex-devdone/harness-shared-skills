# CoreAudio & IOKit Patterns for Raycast Extensions

## Contents
- Aggregate device creation (multi-output routing)
- Volume control on specific devices
- IOHIDManager for hardware key interception
- Permission model

## Aggregate Multi-Output Devices

Create a device that routes audio to multiple outputs simultaneously (e.g., speakers + BlackHole for recording):

```swift
import CoreAudio

let desc: [String: Any] = [
    kAudioAggregateDeviceNameKey as String: "MyApp Output",
    kAudioAggregateDeviceUIDKey as String: "com.myapp.multioutput",
    kAudioAggregateDeviceIsStackedKey as String: 1,  // Required for multi-output
    kAudioAggregateDeviceMasterSubDeviceKey as String: realDeviceUID,
    kAudioAggregateDeviceSubDeviceListKey as String: [
        [kAudioSubDeviceUIDKey as String: realDeviceUID],
        [kAudioSubDeviceUIDKey as String: blackholeUID],
    ],
]

var aggregateDevice = AudioObjectID(0)
let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregateDevice)
```

**Key detail:** `kAudioAggregateDeviceIsStackedKey = 1` is required — without it, the device behaves as an aggregate (clock-synced) rather than multi-output (parallel routing).

**Cleanup:**
```swift
AudioHardwareDestroyAggregateDevice(deviceID)
```

**Wait after creation:** Allow 1 second for macOS audio routing to stabilize before starting recording.

## Volume Control

Aggregate devices don't support hardware volume. Control the real output device directly:

```swift
func getVolume(_ deviceID: AudioObjectID) -> Float {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var volume: Float = 0
    var size = UInt32(MemoryLayout<Float>.size)
    // Try main element, then element 1 (per-channel for built-in output)
    var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    if status == noErr { return volume }
    address.mElement = 1
    status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    return status == noErr ? volume : -1
}

func setVolume(_ deviceID: AudioObjectID, _ volume: Float) {
    let clamped = min(max(volume, 0.0), 1.0)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var vol = clamped
    let size = UInt32(MemoryLayout<Float>.size)
    // Try main, then per-channel (stereo: elements 1 and 2)
    var status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    if status != noErr {
        for ch: UInt32 in 1...2 {
            address.mElement = ch
            vol = clamped
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
        }
    }
}
```

## IOHIDManager for Volume Keys

When an aggregate device is the default output, macOS disables keyboard volume keys entirely — events never reach NSEvent or CGEvent taps. Use IOHIDManager to read raw HID events from the keyboard hardware:

```swift
import IOKit
import IOKit.hid

func monitorVolumeKeys(_ targetDeviceID: UInt32) {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    // Match consumer control devices (keyboards with media keys)
    let matchDict: [String: Any] = [
        kIOHIDDeviceUsagePageKey as String: kHIDPage_Consumer,
        kIOHIDDeviceUsageKey as String: kHIDUsage_Csmr_ConsumerControl,
    ]
    IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

    let ctx = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
    ctx.pointee = targetDeviceID

    IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        guard usagePage == kHIDPage_Consumer, intValue == 1 else { return }

        let deviceID = context!.load(as: UInt32.self)
        let step: Float = 1.0 / 16.0

        switch usage {
        case 0xE9: // Volume Increment
            let vol = getVolume(AudioObjectID(deviceID))
            if vol >= 0 { setVolume(AudioObjectID(deviceID), vol + step) }
        case 0xEA: // Volume Decrement
            let vol = getVolume(AudioObjectID(deviceID))
            if vol >= 0 { setVolume(AudioObjectID(deviceID), vol - step) }
        case 0xE2: // Mute
            toggleMute(AudioObjectID(deviceID))
        default: break
        }
    }, ctx)

    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    CFRunLoopRun()
}
```

**HID Usage IDs (Consumer Control page):**
- `0xE9` — Volume Increment
- `0xEA` — Volume Decrement
- `0xE2` — Mute

**No special permissions required** for standard HID devices.

## Why Other Approaches Fail

| Approach | Result with aggregate device as default |
|---|---|
| `NSEvent.addGlobalMonitorForEvents(.systemDefined)` | Events never delivered — macOS suppresses volume key events entirely |
| `CGEvent.tapCreate` for NX_SYSDEFINED | Same — events blocked before reaching userspace |
| CoreAudio property listener on aggregate device | Aggregate has no volume property to listen to |
| **IOHIDManager** | Works — reads raw keyboard hardware events, bypasses OS-level suppression |

## Compile Command

```bash
swiftc source.swift -o binary -framework CoreAudio -framework IOKit
```

Add `-framework AppKit` only if using NSApplication or NSEvent (not needed for IOHIDManager).
