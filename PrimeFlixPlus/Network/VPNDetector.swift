import Foundation
import SystemConfiguration.CaptiveNetwork
import Combine

struct VPNStatus {
    let isActive: Bool
    let method: String
    let interfaceName: String?
}

class VPNDetector: ObservableObject {
    
    // MARK: - Singleton & Observable State
    static let shared = VPNDetector()
    
    @Published var isVPNActive: Bool = false
    @Published var currentStatus: VPNStatus = VPNStatus(isActive: false, method: "Inactive", interfaceName: nil)
    
    private var timer: Timer?
    
    private init() {
        // Start polling immediately
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startMonitoring() {
        refresh()
        // Poll every 5 seconds to update UI
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func refresh() {
        let status = Self.checkVPNStatus()
        DispatchQueue.main.async {
            // Only publish changes to minimize UI redraws
            if self.isVPNActive != status.isActive {
                self.isVPNActive = status.isActive
            }
            self.currentStatus = status
        }
    }
    
    // MARK: - Detection Logic
    /// Checks for the presence of ACTIVE, ROUTABLE VPN interfaces.
    static func checkVPNStatus() -> VPNStatus {
        // 1. Check System Proxy Settings (Highest Confidence for App VPNs)
        // VPN apps on tvOS usually register a scoped proxy configuration.
        if let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            if let scoped = dict["__SCOPED__"] as? [String: Any] {
                for (key, _) in scoped {
                    if key.contains("tap") || key.contains("tun") || key.contains("ppp") || key.contains("ipsec") {
                        return VPNStatus(isActive: true, method: "System Tunnel (Proxy)", interfaceName: key)
                    }
                    if key.contains("utun") && key != "utun0" {
                         return VPNStatus(isActive: true, method: "System Tunnel (Proxy)", interfaceName: key)
                    }
                }
            }
        }
        
        // 2. Interface Inspection (Fallback with IP Validation)
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
            let addr = interface.ifa_addr
            
            // Standard Flags
            let IFF_UP: Int32 = 0x1
            let IFF_RUNNING: Int32 = 0x40
            
            // Skip Loopback & Inactive Interfaces
            if name == "lo0" || (flags & IFF_UP) != IFF_UP || (flags & IFF_RUNNING) != IFF_RUNNING {
                continue
            }
            
            // Check for VPN candidates
            if name.hasPrefix("ppp") || name.hasPrefix("ipsec") || name.hasPrefix("tap") || name.hasPrefix("tun") || (name.hasPrefix("utun") && name != "utun0") {
                
                // IP ADDRESS CHECK (The Fix for False Positives)
                // We check if the interface has a valid, non-local IP address.
                if let sa = addr {
                    // Filter by Family (IPv4 or IPv6)
                    let family = sa.pointee.sa_family
                    if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                        
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let ipString = String(cString: hostname)
                            
                            // Ignore Link-Local (Auto-IP) addresses often assigned to idle system tunnels
                            // IPv4 Link-Local: 169.254.x.x
                            // IPv6 Link-Local: fe80::...
                            if ipString.hasPrefix("169.254") || ipString.hasPrefix("fe80") {
                                continue
                            }
                            
                            // If we pass these checks, it's a real, active tunnel.
                            vpnInterface = name
                            break
                        }
                    }
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
