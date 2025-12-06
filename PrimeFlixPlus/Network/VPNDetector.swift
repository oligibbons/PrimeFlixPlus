import Foundation
import SystemConfiguration.CaptiveNetwork

struct VPNStatus {
    let isActive: Bool
    let method: String
    let interfaceName: String?
}

class VPNDetector {
    
    /// Checks for the presence of ACTIVE VPN interfaces.
    static func checkVPNStatus() -> VPNStatus {
        // 1. Check System Proxy Settings (High Level - Best for App-based VPNs)
        if let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            if let scoped = dict["__SCOPED__"] as? [String: Any] {
                for (key, _) in scoped {
                    if key.contains("tap") || key.contains("tun") || key.contains("ppp") || key.contains("ipsec") {
                        return VPNStatus(isActive: true, method: "System Tunnel", interfaceName: key)
                    }
                    // Exclude utun0 (often system reserved) unless it's the only one
                    if key.contains("utun") && key != "utun0" {
                         return VPNStatus(isActive: true, method: "System Tunnel", interfaceName: key)
                    }
                }
            }
        }
        
        // 2. Check Interface List directly (Low Level - Best for Network Extensions)
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            return VPNStatus(isActive: false, method: "Error", interfaceName: nil)
        }
        
        var ptr = ifaddr
        var vpnInterface: String?
        
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            
            // Flag constants (Standard BSD/Darwin)
            let IFF_UP: Int32 = 0x1
            let IFF_RUNNING: Int32 = 0x40
            
            // Skip Loopback
            if name == "lo0" { continue }
            
            // Check if interface is UP and RUNNING
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            
            if isUp && isRunning {
                // Check for VPN specific naming conventions
                if name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                    vpnInterface = name
                    break
                }
                
                if name.hasPrefix("utun") && name != "utun0" {
                    vpnInterface = name
                    break
                }
                
                // On some tvOS versions, WireGuard might use utun0 if it's the first networking stack loaded
                // We double check if it's NOT the primary wifi (en0/en1)
                if name.hasPrefix("utun") && !name.hasPrefix("en") && !name.hasPrefix("awdl") && !name.hasPrefix("llw") {
                     // Potential VPN, keep scanning for a better candidate or accept it
                     vpnInterface = name
                }
            }
        }
        
        freeifaddrs(ifaddr)
        
        if let iface = vpnInterface {
            return VPNStatus(isActive: true, method: "Active Tunnel", interfaceName: iface)
        }
        
        return VPNStatus(isActive: false, method: "Direct Connection", interfaceName: nil)
    }
}
