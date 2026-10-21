import Darwin
import Foundation
import WatchKit

enum WatchModelNameResolver {
    static func currentName() -> String {
        guard let identifier = hardwareIdentifier() else {
            return WKInterfaceDevice.current().name
        }

        switch identifier {
        case "Watch5,9", "Watch5,10", "Watch5,11", "Watch5,12":
            return "Apple Watch SE"
        case "Watch6,1", "Watch6,2", "Watch6,3", "Watch6,4":
            return "Apple Watch Series 6"
        case "Watch6,6", "Watch6,7", "Watch6,8", "Watch6,9":
            return "Apple Watch Series 7"
        case "Watch6,10", "Watch6,11", "Watch6,12", "Watch6,13":
            return "Apple Watch SE 2"
        case "Watch6,14", "Watch6,15", "Watch6,16", "Watch6,17":
            return "Apple Watch Series 8"
        case "Watch6,18":
            return "Apple Watch Ultra"
        case "Watch7,1", "Watch7,2", "Watch7,3", "Watch7,4":
            return "Apple Watch Series 9"
        case "Watch7,5":
            return "Apple Watch Ultra 2"
        case "Watch7,8", "Watch7,9", "Watch7,10", "Watch7,11":
            return "Apple Watch Series 10"
        case "Watch7,12":
            return "Apple Watch Ultra 3"
        case "Watch7,13", "Watch7,14", "Watch7,15", "Watch7,16":
            return "Apple Watch SE 3"
        case "Watch7,17", "Watch7,18", "Watch7,19", "Watch7,20":
            return "Apple Watch Series 11"
        case "Watch8,1":
            return "Apple Watch Ultra 4"
        case "Watch8,2", "Watch8,3", "Watch8,4", "Watch8,5":
            return "Apple Watch Series 12"
        default:
            return WKInterfaceDevice.current().name
        }
    }

    private static func hardwareIdentifier() -> String? {
        var length = 0
        guard sysctlbyname("hw.machine", nil, &length, nil, 0) == 0,
              length > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: length)
        let result = buffer.withUnsafeMutableBufferPointer { bytes in
            sysctlbyname("hw.machine", bytes.baseAddress, &length, nil, 0)
        }
        guard result == 0 else { return nil }

        return String(cString: buffer)
    }
}
