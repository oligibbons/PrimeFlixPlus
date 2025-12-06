// oligibbons/primeflixplus/PrimeFlixPlus-2905e8f1ef297ec80428d1d457d9180e78b21452/PrimeFlixPlus/ViewModels/NetworkSpeedTester.swift

import Foundation
import Combine
import SwiftUI

// MARK: - Network Speed Model
struct SpeedTestResult {
    let downloadSpeedMbps: Double
    let expectedQuality: String
    let latencyMs: Int
    let jitterMs: Int
    let testDate: Date
    let statusMessage: String
    
    // VPN Info
    let vpnActive: Bool
    let publicIP: String
    let ispName: String
    let location: String
    
    static func determineQuality(from speed: Double) -> String {
        switch speed {
        case 0..<5.0:
            return "SD (480p) Ready"
        case 5.0..<10.0:
            return "HD (720p) Ready"
        case 10.0..<25.0:
            return "Full HD (1080p) Ready"
        case 25.0..<50.0:
            return "4K UHD (Standard) Ready"
        case 50.0..<100.0:
            return "4K UHD (High Bitrate) Ready"
        default:
            return "8K / Lossless Ready"
        }
    }
}

// MARK: - ViewModel (MainActor Isolated)
@MainActor
class NetworkSpeedTester: ObservableObject {
    
    enum TestStage {
        case idle
        case initialCheck
        case download
        case processing
        case complete
        case failed
    }
    
    @Published var stage: TestStage = .idle
    @Published var progressPercent: Double = 0.0
    @Published var currentSpeedMbps: Double = 0.0
    @Published var currentStatus: String = "Ready to test"
    @Published var result: SpeedTestResult?
    
    // Live VPN Feedback
    @Published var isVpnActive: Bool = false
    @Published var vpnInterfaceName: String? = nil
    
    // Configuration
    // Using a reliable test file (Cloudflare 100MB)
    private let testURL = URL(string: "http://speedtest.tele2.net/100MB.zip")!
    
    // Logic Dependencies
    private var session: URLSession!
    private var sessionDelegate: SpeedTestSessionDelegate?
    
    // IP Data
    private var fetchedIP: String = "Unknown"
    private var fetchedISP: String = "Unknown"
    private var fetchedLocation: String = "Unknown"
    
    func startTest() async {
        guard stage == .idle || stage == .complete || stage == .failed else { return }
        
        // 1. Reset UI
        withAnimation {
            stage = .initialCheck
            progressPercent = 0.0
            currentSpeedMbps = 0.0
            currentStatus = "Analyzing Network Configuration..."
            result = nil
            isVpnActive = false
            vpnInterfaceName = nil
        }
        
        // 2. Check VPN Immediately
        let vpnStatus = VPNDetector.checkVPNStatus()
        withAnimation {
            self.isVpnActive = vpnStatus.isActive
            self.vpnInterfaceName = vpnStatus.interfaceName
        }
        
        // 3. Fetch Public IP / Location (Async)
        // We do this concurrently while preparing the download
        await fetchPublicIPInfo()
        
        // 4. Initialize Session & Delegate
        let delegate = SpeedTestSessionDelegate()
        self.sessionDelegate = delegate
        
        // Setup Callbacks
        delegate.onProgress = { [weak self] mbps, progress in
            Task { @MainActor [weak self] in
                self?.currentSpeedMbps = mbps
                self?.progressPercent = progress
            }
        }
        
        delegate.onFinish = { [weak self] bytes, duration, latency in
            Task { @MainActor [weak self] in
                self?.finalizeTest(totalBytes: bytes, duration: duration, latency: latency)
            }
        }
        
        delegate.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleError(error)
            }
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        // 5. Run Latency Test
        do {
            let latencyStart = Date()
            var request = URLRequest(url: testURL)
            request.httpMethod = "HEAD"
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let latencyEnd = Date()
            let latency = Int(latencyEnd.timeIntervalSince(latencyStart) * 1000)
            
            delegate.capturedLatency = latency
            
            // 6. Start Download Test
            withAnimation {
                self.stage = .download
                self.currentStatus = self.isVpnActive ? "Testing VPN Throughput..." : "Measuring Downstream Bandwidth..."
            }
            
            let task = session.downloadTask(with: testURL)
            delegate.markStartTime()
            task.resume()
            
        } catch {
            handleError(error)
        }
    }
    
    private func fetchPublicIPInfo() async {
        // Simple free API to get connection info
        guard let url = URL(string: "http://ip-api.com/json/?fields=query,isp,country") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                await MainActor.run {
                    self.fetchedIP = json["query"] as? String ?? "Unknown"
                    self.fetchedISP = json["isp"] as? String ?? "Unknown"
                    self.fetchedLocation = json["country"] as? String ?? "Unknown"
                    
                    self.currentStatus = "Public IP: \(self.fetchedIP)"
                }
            }
        } catch {
            print("Failed to fetch IP info: \(error)")
        }
    }
    
    private func handleError(_ error: Error) {
        withAnimation {
            self.stage = .failed
            self.currentStatus = "Error: \(error.localizedDescription)"
            self.progressPercent = 0.0
        }
    }
    
    private func finalizeTest(totalBytes: Int64, duration: TimeInterval, latency: Int) {
        let speedMbps = (Double(totalBytes) * 8.0) / (duration * 1_000_000.0)
        let jitter = Int.random(in: 1...min(latency, 20)) // Simulation for now
        let quality = SpeedTestResult.determineQuality(from: speedMbps)
        
        withAnimation {
            self.currentSpeedMbps = speedMbps
            self.progressPercent = 1.0
            
            self.result = SpeedTestResult(
                downloadSpeedMbps: speedMbps,
                expectedQuality: quality,
                latencyMs: latency,
                jitterMs: jitter,
                testDate: Date(),
                statusMessage: "Success",
                vpnActive: self.isVpnActive,
                publicIP: self.fetchedIP,
                ispName: self.fetchedISP,
                location: self.fetchedLocation
            )
            
            self.stage = .complete
            self.currentStatus = "Test Complete"
        }
        
        self.session.invalidateAndCancel()
    }
}

// MARK: - Background Session Delegate
class SpeedTestSessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    
    // Thread-safe state
    private var startTime: Date?
    var capturedLatency: Int = 0
    
    // Callbacks
    var onProgress: ((Double, Double) -> Void)?
    var onFinish: ((Int64, TimeInterval, Int) -> Void)?
    var onError: ((Error) -> Void)?
    
    func markStartTime() {
        self.startTime = Date()
    }
    
    // 1. Progress Updates
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        guard let start = self.startTime else { return }
        let now = Date()
        let timeElapsed = now.timeIntervalSince(start)
        
        if timeElapsed > 0.5 {
            let currentMbps = (Double(totalBytesWritten) * 8.0) / (timeElapsed * 1_000_000.0)
            let progress: Double
            if totalBytesExpectedToWrite > 0 {
                progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            } else {
                progress = min(0.9, timeElapsed / 10.0)
            }
            
            onProgress?(currentMbps, progress)
        }
    }
    
    // 2. Task Completion
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    
    // 3. Metrics Collection
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        
        let bytes = transaction.countOfResponseBodyBytesReceived
        let duration: TimeInterval
        if let start = transaction.responseStartDate, let end = transaction.responseEndDate {
            duration = end.timeIntervalSince(start)
        } else {
            duration = task.countOfBytesReceived > 0 ? Date().timeIntervalSince(self.startTime ?? Date()) : 1.0
        }
        
        onFinish?(bytes, duration, self.capturedLatency)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onError?(error)
        }
    }
}
