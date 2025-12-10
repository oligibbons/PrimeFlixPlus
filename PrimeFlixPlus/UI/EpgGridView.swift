import SwiftUI
import Combine
import CoreData

// MARK: - View Model
@MainActor
class EpgGridViewModel: ObservableObject {
    
    // Data Source
    @Published var channels: [Channel] = []
    @Published var filteredChannels: [Channel] = []
    @Published var searchText: String = ""
    
    // EPG State
    @Published var programs: [String: [Programme]] = [:] // Map: ChannelURL -> Sorted Programs
    @Published var timeSlots: [Date] = []
    
    // Dependencies
    private var repository: PrimeFlixRepository?
    private var epgService: EpgService?
    private var cancellables = Set<AnyCancellable>()
    
    // Layout Constants
    let slotDuration: TimeInterval = 1800 // 30 mins
    let totalHours = 12
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.epgService = EpgService(context: repository.container.viewContext)
        
        generateTimeSlots()
        loadChannels()
        setupSearch()
    }
    
    // MARK: - Data Loading
    
    private func generateTimeSlots() {
        // Generate slots starting from the previous hour (to show current context)
        let now = Date()
        let cal = Calendar.current
        let startHour = cal.component(.hour, from: now)
        
        guard let startOfHour = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: now) else { return }
        
        var slots: [Date] = []
        for i in 0..<(totalHours * 2) { // 12 hours * 2 slots/hr
            let slot = startOfHour.addingTimeInterval(TimeInterval(i) * slotDuration)
            slots.append(slot)
        }
        self.timeSlots = slots
    }
    
    private func loadChannels() {
        guard let repo = repository else { return }
        // Fetch all Live Channels
        Task {
            if let pl = repo.getAllPlaylists().first {
                let all = repo.getBrowsingContent(playlistUrl: pl.url, type: "live", group: "All")
                self.channels = all
                self.filterChannels()
            }
        }
    }
    
    private func setupSearch() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.filterChannels() }
            .store(in: &cancellables)
    }
    
    private func filterChannels() {
        if searchText.isEmpty {
            self.filteredChannels = channels
        } else {
            self.filteredChannels = channels.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.group.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // MARK: - EPG Management
    
    func fetchEpg(for channel: Channel) {
        guard let service = epgService else { return }
        
        // 1. Check if we already have data
        if programs[channel.url] != nil {
            // Optional: Check if stale
            return
        }
        
        Task {
            // 2. Refresh Remote
            await service.refreshEpg(for: [channel])
            
            // 3. Fetch Local Schedule
            let schedule = service.getSchedule(for: channel)
            
            await MainActor.run {
                self.programs[channel.url] = schedule
            }
        }
    }
    
    func programFor(channel: Channel, time: Date) -> Programme? {
        guard let list = programs[channel.url] else { return nil }
        // Find program active at 'time'
        return list.first { $0.start <= time && $0.end > time }
    }
}

// MARK: - Main View
struct EpgGridView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @StateObject private var viewModel = EpgGridViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    @FocusState private var focusedField: String?
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header & Search
                HStack(spacing: 20) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(CinemeltTheme.cream)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.card)
                    .focused($focusedField, equals: "back")
                    
                    VStack(alignment: .leading) {
                        Text("TV Guide")
                            .font(CinemeltTheme.fontTitle(40))
                            .foregroundColor(CinemeltTheme.cream)
                            .cinemeltGlow()
                        
                        Text(currentDateString)
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Find Channel...", text: $viewModel.searchText)
                            .font(CinemeltTheme.fontBody(22))
                            .foregroundColor(.white)
                            .submitLabel(.search)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .frame(width: 400)
                    .focused($focusedField, equals: "search")
                }
                .padding(40)
                .background(Color.black.opacity(0.5))
                
                // MARK: - Time Headers
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // Spacer for Channel Column
                        Color.clear.frame(width: 220)
                        
                        ForEach(viewModel.timeSlots, id: \.self) { time in
                            Text(formatTime(time))
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(.gray)
                                .frame(width: 250, alignment: .leading)
                                .padding(.leading, 10)
                        }
                    }
                    .padding(.vertical, 15)
                }
                .disabled(true) // Disable interaction, it moves with content if we sync, but for MVP we keep static headers
                
                // MARK: - Grid Content
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 15) {
                        ForEach(viewModel.filteredChannels) { channel in
                            EpgChannelRow(
                                channel: channel,
                                viewModel: viewModel,
                                onPlay: onPlay
                            )
                            .onAppear {
                                viewModel.fetchEpg(for: channel)
                            }
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil { focusedField = "search" }
            }
        }
        .onExitCommand { onBack() }
    }
    
    private var currentDateString: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: Date())
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Row Component
struct EpgChannelRow: View {
    let channel: Channel
    @ObservedObject var viewModel: EpgGridViewModel
    var onPlay: (Channel) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            
            // 1. Sticky Channel Header (Left)
            Button(action: { onPlay(channel) }) {
                HStack {
                    AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv")
                            .foregroundColor(.gray)
                    }
                    .frame(width: 50, height: 50)
                    .cornerRadius(8)
                    
                    Text(channel.title)
                        .font(CinemeltTheme.fontBody(20))
                        .fontWeight(.bold)
                        .foregroundColor(isFocused ? .black : CinemeltTheme.cream)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(10)
                .frame(width: 220, height: 100)
                .background(isFocused ? CinemeltTheme.accent : Color.white.opacity(0.05))
                .cornerRadius(12)
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .zIndex(1)
            
            // 2. Program Timeline
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    if let schedule = viewModel.programs[channel.url], !schedule.isEmpty {
                        // Render Actual Programs
                        // We filter to only show programs that intersect with our 12h window
                        ForEach(schedule) { prog in
                            if let width = calculateWidth(start: prog.start, end: prog.end) {
                                EpgProgramCell(program: prog, width: width, onPlay: { onPlay(channel) })
                            }
                        }
                    } else {
                        // Empty State (No EPG)
                        Text("No Information Available")
                            .font(CinemeltTheme.fontBody(18))
                            .foregroundColor(.gray.opacity(0.5))
                            .frame(width: 800, height: 80)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(8)
                            .padding(.leading, 10)
                    }
                }
                .padding(.leading, 10)
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 40)
    }
    
    // Dynamic Width Calculation based on duration
    // 30 mins = 250pt width
    private func calculateWidth(start: Date, end: Date) -> CGFloat? {
        let duration = end.timeIntervalSince(start)
        let hours = duration / 3600.0
        let width = CGFloat(hours * 500.0) // 500pt per hour
        
        // Filter out tiny programs or huge outliers
        if width < 50 { return 50 }
        if width > 2000 { return 2000 }
        
        return width
    }
}

// MARK: - Program Cell
struct EpgProgramCell: View {
    let program: Programme
    let width: CGFloat
    let onPlay: () -> Void
    
    @FocusState private var isCellFocused: Bool
    
    var isLive: Bool {
        let now = Date()
        return now >= program.start && now < program.end
    }
    
    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(program.title)
                        .font(CinemeltTheme.fontBody(18))
                        .fontWeight(isLive ? .bold : .regular)
                        .foregroundColor(isCellFocused ? .black : (isLive ? CinemeltTheme.accent : .white))
                        .lineLimit(1)
                    
                    if isLive {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                    }
                    Spacer()
                }
                
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(isCellFocused ? .black.opacity(0.7) : .gray)
            }
            .padding(10)
            .frame(width: width, height: 80, alignment: .leading)
            .background(
                ZStack {
                    if isCellFocused {
                        CinemeltTheme.accent
                    } else {
                        Color.white.opacity(isLive ? 0.15 : 0.05)
                    }
                }
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isLive ? CinemeltTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain) // Essential for grid cells to avoid card scaling issues
        .focused($isCellFocused)
        .scaleEffect(isCellFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.2), value: isCellFocused)
    }
    
    private var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: program.start)) - \(f.string(from: program.end))"
    }
}
