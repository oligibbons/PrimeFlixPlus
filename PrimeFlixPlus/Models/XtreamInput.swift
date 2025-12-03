import Foundation

struct XtreamInput {
    let basicUrl: String
    let username: String
    let password: String
    let type: String
    
    static func decodeFromPlaylistUrl(_ urlString: String) -> XtreamInput {
        // 1. Handle "Packed" Format (url|username|password)
        if urlString.contains("|") {
            let parts = urlString.split(separator: "|").map { String($0) }
            var url = parts.indices.contains(0) ? parts[0] : ""
            let user = parts.indices.contains(1) ? parts[1] : ""
            let pass = parts.indices.contains(2) ? parts[2] : ""
            
            // Sanitize spaces
            url = url.replacingOccurrences(of: ": //", with: "://")
                     .replacingOccurrences(of: " ", with: "")
            
            // Remove script name if present
            if url.hasSuffix("/player_api.php") {
                url = String(url.dropLast("/player_api.php".count))
            }
            // Remove trailing slash
            if url.hasSuffix("/") {
                url = String(url.dropLast())
            }
            
            return XtreamInput(
                basicUrl: url,
                username: user,
                password: pass,
                type: DataSourceType.XtreamConstants.typeLive
            )
        }
        
        // 2. Handle Standard URL (fallback)
        guard let urlComponents = URLComponents(string: urlString) else {
            return XtreamInput(basicUrl: urlString, username: "", password: "", type: DataSourceType.XtreamConstants.typeLive)
        }
        
        let scheme = urlComponents.scheme ?? "http"
        let host = urlComponents.host ?? ""
        let portStr = (urlComponents.port != nil) ? ":\(urlComponents.port!)" : ""
        
        // Preserve custom paths
        var path = urlComponents.path
        if path.hasSuffix("/player_api.php") {
            path = String(path.dropLast("/player_api.php".count))
        }
        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        
        // Reconstruct
        let basicUrl = "\(scheme)://\(host)\(portStr)\(path)"
        
        // Extract credentials
        var username = ""
        var password = ""
        var action = ""
        
        if let queryItems = urlComponents.queryItems {
            username = queryItems.first(where: { $0.name == "username" })?.value ?? ""
            password = queryItems.first(where: { $0.name == "password" })?.value ?? ""
            action = queryItems.first(where: { $0.name == "action" })?.value ?? ""
        }
        
        let type: String
        switch action {
        case "get_series": type = DataSourceType.XtreamConstants.typeSeries
        case "get_vod_streams": type = DataSourceType.XtreamConstants.typeVod
        default: type = DataSourceType.XtreamConstants.typeLive
        }
        
        return XtreamInput(
            basicUrl: basicUrl.replacingOccurrences(of: " ", with: ""),
            username: username,
            password: password,
            type: type
        )
    }
}
