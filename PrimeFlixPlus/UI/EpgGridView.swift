import SwiftUI
import Combine
import CoreData

// MARK: - Filter Models
enum EpgFilterMode: String, CaseIterable, Codable {
    case myChannels = "My Channels"
    case custom = "Category Select"
    case all = "All Channels"
}

// MARK: - View Model
@MainActor
class EpgGridViewModel: ObservableObject {
    
    // --- Data Source ---
    @Published var filteredChannels: [Channel] = []
    @Published var allChannels: [Channel] = []
    
    // --- Filter State ---
    @Published var filterMode: EpgFilterMode = .myChannels {
        didSet { saveState(); applyFilters() }
    }
    @Published var selectedCategories: Set<String> = [] {
        didSet { saveState(); applyFilters() }
    }
    @Published var searchText: String = ""
    
    // --- Available Metadata ---
    @Published var availableCategories: [String] = []
    @Published var programs: [String: [Programme]] = [:]
    @Published var timeSlots: [Date] = []
    
    // --- Internal State ---
    private var favoriteIds: Set<String> = []
    private var recentIds: Set<String> = []
    
    // --- Dependencies ---
    private var repository: PrimeFlixRepository?
    private var epgService: EpgService?
    private var cancellables = Set<AnyCancellable>()
    
    // --- Constants ---
    let slotDuration: TimeInterval = 1800 // 30 mins
    let totalHours = 12
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.epgService = EpgService(context: repository.container.viewContext)
        
        loadPersistedState()
        generateTimeSlots()
        loadData()
        setupListeners()
    }
    
    // MARK: - Persistence
    
    private func loadPersistedState() {
        // Mode
        if let data = UserDefaults.standard.data(forKey: "epgFilterMode"),
           let mode = try? JSONDecoder().decode(EpgFilterMode.self, from: data) {
            self.filterMode = mode
        }
        
        // Categories
        if let savedCats = UserDefaults.standard.stringArray(forKey: "epgSelectedCategories") {
            self.selectedCategories = Set(savedCats)
        }
    }
    
    private func saveState() {
        if let data = try? JSONEncoder().encode(filterMode) {
            UserDefaults.standard.set(data, forKey: "epgFilterMode")
        }
        UserDefaults.standard.set(Array(selectedCategories), forKey: "epgSelectedCategories")
    }
    
    // MARK: - Data Loading
    
    private func setupListeners() {
        guard let repo = repository else { return }
        
        // 1. Search Debounce
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFilters() }
            .store(in: &cancellables)
            
        // 2. Repository Updates (Fixes "No Channels" on cold start)
        repo.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadData()
            }
            .store(in: &cancellables)
    }
    
    private func loadData() {
        guard let repo = repository else { return }
        
        Task {
            // 1. Fetch Metadata (Favs/Recents)
            // Always refetch these as they change dynamically
            let favs = repo.getFavorites(type: "live")
            let recents = repo.getSmartContinueWatching(type: "live")
            
            let newFavIds = Set(favs.map { $0.url })
            let newRecentIds = Set(recents.map { $0.url })
            
            await MainActor.run {
                self.favoriteIds = newFavIds
                self.recentIds = newRecentIds
            }
            
            // 2. Fetch All Channels (Only if needed or empty)
            if self.allChannels.isEmpty {
                if let pl = repo.getAllPlaylists().first {
                    let all = repo.getBrowsingContent(playlistUrl: pl.url, type: "live", group: "All")
                    let groups = Set(all.map { $0.group }).sorted()
                    
                    await MainActor.run {
                        self.allChannels = all
                        self.availableCategories = groups
                        self.applyFilters()
                    }
                }
            } else {
                // If channels already loaded, just re-apply filters with new Favs/Recents
                await MainActor.run {
                    self.applyFilters()
                }
            }
        }
    }
    
    // MARK: - Filter Logic (The Core)
    
    func applyFilters() {
        var result: [Channel] = []
        
        // 1. Apply Mode
        switch filterMode {
        case .myChannels:
            // Combine Favorites + Recents (Deduplicated)
            result = allChannels.filter {
                favoriteIds.contains($0.url) || recentIds.contains($0.url)
            }
            // Sort: Favorites first, then Recents
            result.sort { (a, b) -> Bool in
                if favoriteIds.contains(a.url) && !favoriteIds.contains(b.url) { return true }
                if !favoriteIds.contains(a.url) && favoriteIds.contains(b.url) { return false }
                return a.title < b.title
            }
            
        case .custom:
            result = allChannels.filter { selectedCategories.contains($0.group) }
            
        case .all:
            result = allChannels
        }
        
        // 2. Apply Search
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.group.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 3. Cap for Performance (Safety net)
        self.filteredChannels = Array(result.prefix(1000))
    }
    
    // MARK: - EPG & Time
    
    private func generateTimeSlots() {
        let now = Date()
        let cal = Calendar.current
        let startHour = cal.component(.hour, from: now)
        guard let startOfHour = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: now) else { return }
        
        var slots: [Date] = []
        for i in -1..<(totalHours * 2) {
            slots.append(startOfHour.addingTimeInterval(TimeInterval(i) * slotDuration))
        }
        self.timeSlots = slots
    }
    
    func fetchEpg(for channel: Channel) {
        guard let service = epgService, programs[channel.url] == nil else { return }
        
        Task {
            await service.refreshEpg(for: [channel])
            let schedule = service.getSchedule(for: channel)
            self.programs[channel.url] = schedule // Direct assignment on MainActor
        }
    }
    
    func toggleCategory(_ cat: String) {
        if selectedCategories.contains(cat) {
            selectedCategories.remove(cat)
        } else {
            selectedCategories.insert(cat)
        }
    }
}

// MARK: - Main View
struct EpgGridView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @StateObject private var viewModel = EpgGridViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    @State private var showFilterSettings: Bool = false
    @FocusState private var focusedField: String?
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header
                HStack(spacing: 20) {
                    // Back
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
                    
                    // Title & Mode
                    VStack(alignment: .leading) {
                        Text("TV Guide")
                            .font(CinemeltTheme.fontTitle(40))
                            .foregroundColor(CinemeltTheme.cream)
                            .cinemeltGlow()
                        
                        HStack {
                            Text(currentDateString)
                            Text("•")
                            Text(viewModel.filterMode.rawValue)
                                .foregroundColor(CinemeltTheme.accent)
                                .fontWeight(.bold)
                        }
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Filter Button
                    Button(action: { showFilterSettings = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("Filter")
                        }
                        .font(CinemeltTheme.fontBody(22))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(CinemeltTheme.accent)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.card)
                    .focused($focusedField, equals: "filter")
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search...", text: $viewModel.searchText)
                            .font(CinemeltTheme.fontBody(22))
                            .foregroundColor(.white)
                            .submitLabel(.search)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .frame(width: 300)
                    .focused($focusedField, equals: "search")
                }
                .padding(40)
                .background(Color.black.opacity(0.6))
                
                // MARK: - Time Headers
                HStack(spacing: 0) {
                    Color.clear.frame(width: 220) // Channel Column Spacer
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(viewModel.timeSlots, id: \.self) { time in
                                Text(formatTime(time))
                                    .font(CinemeltTheme.fontBody(20))
                                    .foregroundColor(.gray)
                                    .frame(width: 250, alignment: .leading)
                                    .padding(.leading, 10)
                                    .overlay(
                                        Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1),
                                        alignment: .leading
                                    )
                            }
                        }
                    }
                    .disabled(true)
                }
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.3))
                
                // MARK: - Grid Content
                if viewModel.filteredChannels.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "tv.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No channels found.")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.cream)
                        
                        if viewModel.filterMode == .myChannels {
                            Text("You haven't added any favorites or watched live TV yet.")
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(.gray)
                        } else {
                            Text("Try changing your filter settings.")
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(.gray)
                        }
                        
                        Button("Change Filter") { showFilterSettings = true }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .padding(.top, 20)
                        
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 15) {
                            ForEach(viewModel.filteredChannels) { channel in
                                EpgChannelRow(
                                    channel: channel,
                                    viewModel: viewModel,
                                    onPlay: onPlay
                                )
                                .onAppear { viewModel.fetchEpg(for: channel) }
                            }
                        }
                        .padding(.bottom, 50)
                    }
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
        .sheet(isPresented: $showFilterSettings) {
            EpgFilterSettingsView(viewModel: viewModel)
        }
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

// MARK: - Filter Settings Sheet
struct EpgFilterSettingsView: View {
    @ObservedObject var viewModel: EpgGridViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Modes
            VStack(alignment: .leading, spacing: 30) {
                Text("View Mode")
                    .font(CinemeltTheme.fontTitle(40))
                    .foregroundColor(CinemeltTheme.cream)
                    .padding(.top, 40)
                
                ForEach(EpgFilterMode.allCases, id: \.self) { mode in
                    Button(action: {
                        viewModel.filterMode = mode
                    }) {
                        HStack {
                            Text(mode.rawValue)
                                .font(CinemeltTheme.fontBody(26))
                                .fontWeight(viewModel.filterMode == mode ? .bold : .regular)
                            Spacer()
                            if viewModel.filterMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding()
                        .background(viewModel.filterMode == mode ? CinemeltTheme.accent : Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .foregroundColor(viewModel.filterMode == mode ? .black : .white)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
                
                Spacer()
                
                Button("Done") { presentationMode.wrappedValue.dismiss() }
                    .font(CinemeltTheme.fontTitle(30))
                    .buttonStyle(CinemeltCardButtonStyle())
                    .padding(.bottom, 40)
            }
            .frame(width: 400)
            .padding(.horizontal, 40)
            .background(CinemeltTheme.charcoal)
            
            Divider()
            
            // Right: Categories (Only if Custom)
            if viewModel.filterMode == .custom {
                VStack(alignment: .leading) {
                    Text("Select Categories")
                        .font(CinemeltTheme.fontTitle(40))
                        .foregroundColor(CinemeltTheme.cream)
                        .padding(.top, 40)
                        .padding(.bottom, 20)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 20) {
                            ForEach(viewModel.availableCategories, id: \.self) { cat in
                                Button(action: { viewModel.toggleCategory(cat) }) {
                                    HStack {
                                        Text(cat)
                                            .font(CinemeltTheme.fontBody(20))
                                            .lineLimit(1)
                                        Spacer()
                                        if viewModel.selectedCategories.contains(cat) {
                                            Image(systemName: "checkmark.square.fill")
                                                .foregroundColor(CinemeltTheme.accent)
                                        } else {
                                            Image(systemName: "square")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
                .padding(.horizontal, 40)
                .background(CinemeltTheme.mainBackground)
            } else {
                // Info Placeholder
                VStack {
                    Spacer()
                    Image(systemName: viewModel.filterMode == .myChannels ? "heart.text.square" : "list.bullet.rectangle")
                        .font(.system(size: 100))
                        .foregroundColor(CinemeltTheme.accent.opacity(0.5))
                        .padding(.bottom, 20)
                    
                    Text(viewModel.filterMode == .myChannels
                         ? "Showing only your Favorites and Recently Watched channels."
                         : "Showing all channels from the library.")
                        .font(CinemeltTheme.fontTitle(30))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 50)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(CinemeltTheme.mainBackground)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Row Component (Unchanged from prev)
struct EpgChannelRow: View {
    let channel: Channel
    @ObservedObject var viewModel: EpgGridViewModel
    var onPlay: (Channel) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            
            Button(action: { onPlay(channel) }) {
                HStack {
                    AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv").foregroundColor(.gray)
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
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    if let schedule = viewModel.programs[channel.url], !schedule.isEmpty {
                        ForEach(schedule) { prog in
                            if let width = calculateWidth(start: prog.start, end: prog.end) {
                                EpgProgramCell(program: prog, width: width, onPlay: { onPlay(channel) })
                            }
                        }
                    } else {
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
    
    private func calculateWidth(start: Date, end: Date) -> CGFloat? {
        let duration = end.timeIntervalSince(start)
        let width = CGFloat((duration / 3600.0) * 500.0)
        if width < 50 { return 50 }
        if width > 3000 { return 3000 }
        return width
    }
}

// MARK: - Program Cell (Unchanged from prev)
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
                    
                    if isLive { Circle().fill(Color.red).frame(width: 6, height: 6) }
                    Spacer()
                }
                
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(isCellFocused ? .black.opacity(0.7) : .gray)
            }
            .padding(10)
            .frame(width: width - 4, height: 80, alignment: .leading)
            .background(
                ZStack {
                    if isCellFocused { CinemeltTheme.accent }
                    else { Color.white.opacity(isLive ? 0.15 : 0.05) }
                }
            )
            .cornerRadius(8)
            .padding(.trailing, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isLive ? CinemeltTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

}

**Next Step:**
We're almost done with the critical updates. The next item is to ensure that opening secondary pages (**Favorites**, **Watchlist**, **Continue Watching**) selects the **content** first, not the sidebar.
This involves a small tweak to:
1.  **`FavoritesView.swift`**
2.  **`WatchlistView.swift`**
3.  **`ContinueWatchingView.swift`**

I'll provide **`FavoritesView.swift`** first.
