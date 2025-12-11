import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void
    @EnvironmentObject var repository: PrimeFlixRepository
    @StateObject private var viewModel = OnboardingViewModel()
    
    // Focus Management
    @FocusState private var focusedMood: String?
    @FocusState private var focusedGenre: String?
    @FocusState private var isNextButtonFocused: Bool
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack {
                switch viewModel.step {
                case .intro:
                    introStep.transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                case .moods:
                    moodsStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .genres:
                    genresStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .favorites:
                    favoritesStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .processing:
                    processingStep.transition(.opacity)
                case .done:
                    doneStep.transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.5), value: viewModel.step)
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
    }
    
    // MARK: - Step 1-3 (Unchanged)
    
    var introStep: some View {
        VStack(spacing: 40) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 100))
                .foregroundColor(CinemeltTheme.accent)
                .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 30)
            
            Text("Welcome to Cinemelt")
                .font(CinemeltTheme.fontTitle(70))
                .foregroundColor(CinemeltTheme.cream)
                .cinemeltGlow()
            
            Text("Let's personalize your cinema experience.\nTell us what you love, and we'll handle the rest.")
                .font(CinemeltTheme.fontBody(32))
                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 100)
            
            Button(action: { viewModel.nextStep() }) {
                Text("Get Started")
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(.black)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
                    .background(CinemeltTheme.accent)
                    .cornerRadius(16)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .padding(.top, 40)
        }
    }
    
    var moodsStep: some View {
        StepContainer(
            title: "What's the vibe?",
            subtitle: "Select moods that resonate with you.",
            onNext: { viewModel.nextStep() },
            canProceed: !viewModel.selectedMoods.isEmpty
        ) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 40)], spacing: 40) {
                    ForEach(viewModel.availableMoods, id: \.self) { mood in
                        SelectableCard(
                            label: mood,
                            isSelected: viewModel.selectedMoods.contains(mood),
                            action: { viewModel.toggleMood(mood) }
                        )
                        .focused($focusedMood, equals: mood)
                    }
                }
                .padding(60)
            }
        }
    }
    
    var genresStep: some View {
        StepContainer(
            title: "Favorite Genres",
            subtitle: "We'll prioritize these categories for you.",
            onNext: { viewModel.nextStep() },
            canProceed: !viewModel.selectedGenres.isEmpty
        ) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 30)], spacing: 30) {
                    ForEach(viewModel.availableGenres, id: \.self) { genre in
                        SelectableCard(
                            label: genre,
                            isSelected: viewModel.selectedGenres.contains(genre),
                            action: { viewModel.toggleGenre(genre) }
                        )
                        .focused($focusedGenre, equals: genre)
                    }
                }
                .padding(60)
            }
        }
    }
    
    // MARK: - Step 4: Favorites (Refined)
    
    var favoritesStep: some View {
        StepContainer(
            title: "Your Favorites",
            subtitle: "Search and add shows you've watched. We'll find new seasons for you.",
            buttonText: "Finish Setup",
            onNext: { viewModel.nextStep() },
            canProceed: true
        ) {
            HStack(alignment: .top, spacing: 60) {
                // Left: Input & Search Results
                VStack(spacing: 20) {
                    GlassTextField(
                        title: "Search TMDB",
                        placeholder: "Enter show or movie name...",
                        text: $viewModel.searchQuery,
                        nextFocus: {}
                    )
                    
                    if viewModel.isSearching {
                        CinemeltLoadingIndicator().scaleEffect(0.5)
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: 15) {
                            ForEach(viewModel.searchResults) { item in
                                Button(action: { viewModel.addFavorite(item) }) {
                                    HStack(spacing: 15) {
                                        AsyncImage(url: item.posterUrl) { img in
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: { Color.gray.opacity(0.3) }
                                        .frame(width: 40, height: 60)
                                        .cornerRadius(4)
                                        
                                        VStack(alignment: .leading) {
                                            Text(item.title)
                                                .font(CinemeltTheme.fontBody(20))
                                                .foregroundColor(CinemeltTheme.cream)
                                            Text("\(item.type.uppercased()) • \(item.year)")
                                                .font(CinemeltTheme.fontBody(16))
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        
                                        // Visual Check if already added
                                        if viewModel.manualFavorites.contains(where: { $0.id == item.id }) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(CinemeltTheme.accent)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                            }
                        }
                    }
                }
                .frame(width: 500)
                
                // Right: Selected List (Interactive)
                VStack(alignment: .leading, spacing: 20) {
                    Text("Selected (\(viewModel.manualFavorites.count))")
                        .font(CinemeltTheme.fontTitle(24))
                        .foregroundColor(CinemeltTheme.cream)
                    
                    if viewModel.manualFavorites.isEmpty {
                        Text("Added shows will appear here.\nScroll here to manage your list.")
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 20)], spacing: 20) {
                                ForEach(viewModel.manualFavorites) { fav in
                                    Button(action: { viewModel.prepareEdit(fav) }) {
                                        ZStack(alignment: .topTrailing) {
                                            // Poster
                                            AsyncImage(url: fav.item.posterUrl) { img in
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: { Color.gray }
                                            .frame(width: 140, height: 210)
                                            .cornerRadius(12)
                                            // Super Favourite Glow
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(fav.isSuper ? Color.yellow : Color.clear, lineWidth: 4)
                                                    .shadow(color: fav.isSuper ? Color.yellow.opacity(0.8) : .clear, radius: 10)
                                            )
                                            
                                            // Super Icon
                                            if fav.isSuper {
                                                Image(systemName: "star.fill")
                                                    .padding(6)
                                                    .background(Circle().fill(Color.yellow))
                                                    .foregroundColor(.black)
                                                    .offset(x: 5, y: -5)
                                                    .shadow(radius: 2)
                                            }
                                        }
                                    }
                                    .buttonStyle(CinemeltCardButtonStyle())
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(40)
            // POPUP MENU FOR FAVORITES
            .confirmationDialog(
                "Manage '\(viewModel.editingFavorite?.item.title ?? "Show")'",
                isPresented: $viewModel.showEditDialog,
                titleVisibility: .visible
            ) {
                if let fav = viewModel.editingFavorite {
                    Button(fav.isSuper ? "Remove Super Status" : "Make Super Favourite") {
                        viewModel.toggleSuperFavorite()
                    }
                    Button("Remove from list", role: .destructive) {
                        viewModel.removeFavorite()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }
    
    // MARK: - Steps 5-6 (Unchanged)
    
    var processingStep: some View {
        VStack(spacing: 30) {
            CinemeltLoadingIndicator()
                .scaleEffect(1.5)
            Text("Personalizing Library...")
                .font(CinemeltTheme.fontTitle(40))
                .foregroundColor(CinemeltTheme.cream)
                .cinemeltGlow()
        }
    }
    
    var doneStep: some View {
        VStack(spacing: 40) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(CinemeltTheme.accent)
                .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 30)
            
            Text("All Set!")
                .font(CinemeltTheme.fontTitle(60))
                .foregroundColor(CinemeltTheme.cream)
            
            Button(action: onComplete) {
                Text("Start Watching")
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(.black)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
                    .background(CinemeltTheme.accent)
                    .cornerRadius(16)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .focused($isNextButtonFocused)
            .onAppear { isNextButtonFocused = true }
        }
    }
}

// MARK: - UI Helpers

struct StepContainer<Content: View>: View {
    let title: String
    let subtitle: String
    var buttonText: String = "Continue"
    let onNext: () -> Void
    let canProceed: Bool
    let content: () -> Content
    
    @FocusState private var isButtonFocused: Bool
    
    var body: some View {
        VStack {
            // Header
            VStack(spacing: 10) {
                Text(title)
                    .font(CinemeltTheme.fontTitle(50))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                Text(subtitle)
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
            }
            .padding(.top, 40)
            
            // Content
            content()
            
            // Footer
            Button(action: onNext) {
                HStack {
                    Text(buttonText)
                    Image(systemName: "arrow.right")
                }
                .font(CinemeltTheme.fontTitle(28))
                .foregroundColor(canProceed ? .black : .gray)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .background(canProceed ? CinemeltTheme.accent : Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .disabled(!canProceed)
            .padding(.bottom, 40)
            .focused($isButtonFocused)
        }
    }
}

struct SelectableCard: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(CinemeltTheme.fontTitle(28))
                .foregroundColor(isSelected ? .black : CinemeltTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(
                    ZStack {
                        if isSelected {
                            CinemeltTheme.accent
                        } else {
                            CinemeltTheme.glassSurface
                        }
                    }
                )
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? CinemeltTheme.accent : Color.white.opacity(0.2), lineWidth: 2)
                )
        }
        .buttonStyle(CinemeltCardButtonStyle())
    }
}
