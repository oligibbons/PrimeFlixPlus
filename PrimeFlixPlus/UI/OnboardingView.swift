import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Callbacks provided by parent
    var onComplete: () -> Void
    
    // Focus State
    @FocusState private var focusedField: OnboardingFocus?
    
    enum OnboardingFocus: Hashable {
        case nextButton
        case item(String) // For Moods/Genres
        case searchBar
        case searchResult(Int)
        case favoriteItem(Int)
    }
    
    // Grid Layouts
    let columns = [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 30)]
    let searchColumns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 30)]
    
    var body: some View {
        ZStack {
            // 1. Background
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            // 2. Content Flow
            VStack {
                switch viewModel.step {
                case .intro:
                    introStep
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading)))
                case .moods:
                    selectionStep(
                        title: "How are you feeling?",
                        subtitle: "Select moods to tailor your recommendations.",
                        items: viewModel.availableMoods,
                        selected: viewModel.selectedMoods,
                        onToggle: { viewModel.toggleMood($0) }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .genres:
                    selectionStep(
                        title: "What do you like?",
                        subtitle: "Pick at least 3 genres you enjoy.",
                        items: viewModel.availableGenres,
                        selected: viewModel.selectedGenres,
                        onToggle: { viewModel.toggleGenre($0) }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .favorites:
                    favoritesStep
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .processing:
                    processingStep
                        .transition(.opacity)
                case .done:
                    doneStep
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.step)
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .nextButton
            }
        }
    }
    
    // MARK: - Steps
    
    private var introStep: some View {
        VStack(spacing: 40) {
            Image("CinemeltLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)
                .cinemeltGlow()
            
            VStack(spacing: 10) {
                Text("Welcome to Cinemelt")
                    .font(CinemeltTheme.fontTitle(60))
                    .foregroundColor(CinemeltTheme.cream)
                
                Text("Let's personalize your experience.")
                    .font(CinemeltTheme.fontBody(28))
                    .foregroundColor(.gray)
            }
            
            Button(action: { viewModel.nextStep() }) {
                Text("Get Started")
                    .font(CinemeltTheme.fontTitle(28))
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                    .background(CinemeltTheme.accent)
                    .cornerRadius(16)
                    .foregroundColor(.black)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .focused($focusedField, equals: .nextButton)
            .padding(.top, 40)
        }
    }
    
    private func selectionStep(title: String, subtitle: String, items: [String], selected: Set<String>, onToggle: @escaping (String) -> Void) -> some View {
        VStack(spacing: 40) {
            VStack(spacing: 10) {
                Text(title)
                    .font(CinemeltTheme.fontTitle(48))
                    .foregroundColor(CinemeltTheme.cream)
                Text(subtitle)
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
            }
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 30) {
                    ForEach(items, id: \.self) { item in
                        Button(action: { onToggle(item) }) {
                            Text(item)
                                .font(CinemeltTheme.fontBody(22))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(
                                    selected.contains(item) ? CinemeltTheme.accent : Color.white.opacity(0.1)
                                )
                                .foregroundColor(selected.contains(item) ? .black : .white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedField, equals: .item(item))
                    }
                }
                .padding(40)
            }
            .focusSection()
            
            Button(action: { viewModel.nextStep() }) {
                HStack {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(CinemeltTheme.fontTitle(24))
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(.white)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .focused($focusedField, equals: .nextButton)
            .disabled(viewModel.step == .genres && selected.count < 3)
            .opacity(viewModel.step == .genres && selected.count < 3 ? 0.5 : 1.0)
        }
        .padding(.vertical, 60)
    }
    
    private var favoritesStep: some View {
        HStack(spacing: 40) {
            // LEFT: Search
            VStack(alignment: .leading, spacing: 20) {
                Text("Add Favorites")
                    .font(CinemeltTheme.fontTitle(36))
                    .foregroundColor(CinemeltTheme.cream)
                
                GlassTextField(
                    title: "Search movies & shows...",
                    placeholder: "e.g. Inception",
                    text: $viewModel.searchQuery,
                    nextFocus: { }
                )
                .focused($focusedField, equals: .searchBar)
                
                ScrollView {
                    LazyVGrid(columns: searchColumns, spacing: 30) {
                        ForEach(viewModel.searchResults) { item in
                            Button(action: { viewModel.addFavorite(item) }) {
                                VStack {
                                    AsyncImage(url: item.posterUrl) { img in
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(height: 240)
                                    .cornerRadius(12)
                                    
                                    Text(item.title)
                                        .font(CinemeltTheme.fontBody(18))
                                        .lineLimit(1)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedField, equals: .searchResult(item.id))
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .focusSection()
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // RIGHT: Selected List
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Your List")
                        .font(CinemeltTheme.fontTitle(36))
                        .foregroundColor(CinemeltTheme.cream)
                    Spacer()
                    Text("\(viewModel.manualFavorites.count) items")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(CinemeltTheme.accent)
                }
                
                ScrollView {
                    LazyVGrid(columns: searchColumns, spacing: 30) {
                        ForEach(viewModel.manualFavorites) { fav in
                            Button(action: { viewModel.prepareEdit(fav) }) {
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: fav.item.posterUrl) { img in
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(height: 240)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(fav.isSuper ? CinemeltTheme.accent : Color.clear, lineWidth: 3)
                                    )
                                    
                                    if fav.isSuper {
                                        Image(systemName: "star.fill")
                                            .padding(8)
                                            .background(CinemeltTheme.accent)
                                            .foregroundColor(.black)
                                            .clipShape(Circle())
                                            .offset(x: 5, y: -5)
                                    }
                                }
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedField, equals: .favoriteItem(fav.id))
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.editingFavorite = fav
                                    viewModel.removeFavorite()
                                } label: { Label("Remove", systemImage: "trash") }
                                
                                Button {
                                    viewModel.editingFavorite = fav
                                    viewModel.toggleSuperFavorite()
                                } label: { Label(fav.isSuper ? "Unmark Super Favorite" : "Mark as Super Favorite", systemImage: "star") }
                            }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .focusSection()
                
                Button(action: { viewModel.nextStep() }) {
                    Text("Finish Profile")
                        .font(CinemeltTheme.fontTitle(24))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(CinemeltTheme.accent)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
                .buttonStyle(CinemeltCardButtonStyle())
                .focused($focusedField, equals: .nextButton)
            }
            .frame(width: 500)
        }
        .padding(50)
        
        // Edit Dialog
        .confirmationDialog(
            "Manage Favorite",
            isPresented: $viewModel.showEditDialog,
            presenting: viewModel.editingFavorite
        ) { fav in
            Button(fav.isSuper ? "Unmark as Super Favorite" : "Mark as Super Favorite") {
                viewModel.toggleSuperFavorite()
            }
            Button("Remove from List", role: .destructive) {
                viewModel.removeFavorite()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private var processingStep: some View {
        VStack(spacing: 30) {
            CinemeltLoadingIndicator()
                .scaleEffect(2.0)
            
            Text("Building your Taste Profile...")
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
            
            Text("Analyzing \(viewModel.selectedGenres.count) genres and \(viewModel.selectedMoods.count) moods.")
                .font(CinemeltTheme.fontBody(20))
                .foregroundColor(.gray)
        }
    }
    
    private var doneStep: some View {
        VStack(spacing: 40) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.green)
                .shadow(color: .green.opacity(0.5), radius: 30)
            
            Text("You're all set!")
                .font(CinemeltTheme.fontTitle(50))
                .foregroundColor(CinemeltTheme.cream)
            
            Button(action: onComplete) {
                Text("Start Watching")
                    .font(CinemeltTheme.fontTitle(28))
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
                    .background(CinemeltTheme.accent)
                    .cornerRadius(16)
                    .foregroundColor(.black)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .focused($focusedField, equals: .nextButton)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .nextButton
            }
        }
    }
}
