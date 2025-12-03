import Foundation

class UnsafeSession: NSObject, URLSessionDelegate {
    
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        // Increased timeouts for slow IPTV servers
        configuration.timeoutIntervalForRequest = 300 // 5 minutes
        configuration.timeoutIntervalForResource = 600 // 10 minutes
        
        // FIX: Removed global User-Agent header.
        // We now let the individual Clients (XtreamClient / AVPlayer) handle this
        // dynamically to support rotation and specific requirements.
        configuration.httpAdditionalHeaders = nil
        
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
