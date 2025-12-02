import Foundation

/// Helper to parse and hold Xtream Codes credentials.
struct XtreamInput {
    let basicUrl: String
    let username: String
    let password: String
    let type: String
    
    // Corresponds to the Companion Object 'decodeFromPlaylistUrl' logic
    static func decodeFromPlaylistUrl(_ urlString: String) -> XtreamInput {
        // 1. Check for internal "packed" format (url|username|password)
        if urlString.contains("|") {
            let parts = urlString.split(separator: "|").map { String($0) }
            let url = parts.indices.contains(0) ? parts[0] : ""
            let user = parts.indices.contains(1) ? parts[1] : ""
            let pass = parts.indices.contains(2) ? parts[2] : ""
            
            return XtreamInput(
                basicUrl: url,
                username: user,
                password: pass,
                type: DataSourceType.XtreamConstants.typeLive
            )
        }
        
        // 2. Fallback: Parse as standard GET request URL
        guard let urlComponents = URLComponents(string: urlString) else {
            // Return empty if parsing fails entirely
            return XtreamInput(basicUrl: urlString, username: "", password: "", type: DataSourceType.XtreamConstants.typeLive)
        }
        
        // Extract scheme and host (reconstruct base URL)
        let scheme = urlComponents.scheme ?? "http"
        let host = urlComponents.host ?? ""
        let portStr = (urlComponents.port != nil) ? ":\(urlComponents.port!)" : ""
        
        // CRITICAL FIX: Removed space between scheme and slash (was ": //")
        let basicUrl = "\(scheme)://\(host)\(portStr)"
        
        // Extract query parameters
        var username = ""
        var password = ""
        var action = ""
        
        if let queryItems = urlComponents.queryItems {
            username = queryItems.first(where: { $0.name == "username" })?.value ?? ""
            password = queryItems.first(where: { $0.name == "password" })?.value ?? ""
            action = queryItems.first(where: { $0.name == "action" })?.value ?? ""
        }
        
        // Determine type based on 'action' parameter
        let type: String
        switch action {
        case "get_series":
            type = DataSourceType.XtreamConstants.typeSeries
        case "get_vod_streams":
            type = DataSourceType.XtreamConstants.typeVod
        default:
            type = DataSourceType.XtreamConstants.typeLive
        }
        
        return XtreamInput(
            basicUrl: basicUrl.replacingOccurrences(of: " ", with: ""), // Sanitize
            username: username,
            password: password,
            type: type
        )
    }
}
