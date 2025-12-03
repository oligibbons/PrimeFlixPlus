import Foundation

class UnsafeSession: NSObject, URLSessionDelegate {
    
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        // Increased timeouts for slow IPTV servers
        configuration.timeoutIntervalForRequest = 300 // 5 minutes
        configuration.timeoutIntervalForResource = 600 // 10 minutes
        
        // CRITICAL FIX: Use VLC User-Agent to match PlayerViewModel
        configuration.httpAdditionalHeaders = [
            "User-Agent": "VLC/3.0.16 LibVLC/3.0.16"
        ]
        
        // Keep the delegate to bypass SSL errors
        return URLSession(configuration: configuration, delegate: UnsafeSession(), delegateQueue: nil)
    }()
    
    // Tells iOS/tvOS to trust ALL certificates (Bypass SSL)
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }
        
        completionHandler(.performDefaultHandling, nil)
    }
}
