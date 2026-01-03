import SwiftUI
import AppKit
import AVFoundation
internal import UniformTypeIdentifiers

struct ScreenshotEditorView: View {
    let originalImage: NSImage
    let onCopy: (NSImage) -> Void
    let onClose: () -> Void
    
    @StateObject private var viewModel: ScreenshotEditorViewModel
    @State private var selectedTab: Int = 0
    @State private var isDraggingScreenshot: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    init(originalImage: NSImage, onCopy: @escaping (NSImage) -> Void, onClose: @escaping () -> Void) {
        self.originalImage = originalImage
        self.onCopy = onCopy
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: ScreenshotEditorViewModel(originalImage: originalImage))
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar with inspector controls
            inspectorContent
                .frame(width: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            // Main canvas
            canvasView
                .toolbar {
                    ToolbarItemGroup {
                        Button("Zoom Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                            viewModel.calculateFitZoom()
                        }
                        Button("Actual Size", systemImage: "1.magnifyingglass") {
                            viewModel.config.zoom = 100
                        }
                    }
                    
                    ToolbarItem {
                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            viewModel.resetPosition()
                        }
                    }
                    
                    ToolbarItemGroup {
                        Button("Save", systemImage: "square.and.arrow.down") {
                            viewModel.saveAction()
                        }
                        Button("Copy", systemImage: "doc.on.doc") {
                            if let img = viewModel.copyAction() { onCopy(img) }
                        }
                    }
                }
        }
        .toolbar(removing: .title)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadWallpapers()
            viewModel.calculateFitZoom()
        }
        // Toolbar action handlers (for keyboard shortcuts)
        .onReceive(NotificationCenter.default.publisher(for: ScreenshotEditorWindow.copyNotification)) { _ in
            if let img = viewModel.copyAction() { onCopy(img) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenshotEditorWindow.saveNotification)) { _ in
            viewModel.saveAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenshotEditorWindow.resetNotification)) { _ in
            viewModel.resetPosition()
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenshotEditorWindow.zoomFitNotification)) { _ in
            viewModel.calculateFitZoom()
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenshotEditorWindow.zoomActualNotification)) { _ in
            viewModel.config.zoom = 100
        }
    }
    
    // MARK: - Inspector Content (Sidebar)
    private var inspectorContent: some View {
        VStack(spacing: 0) {
            // Tab selector at top
            Picker("", selection: $selectedTab.animation(.easeInOut(duration: 0.2))) {
                Text("style").tag(0)
                Text("canvas").tag(1)
                Text("export").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            
            // Content - using Form like Landmarks
            Form {
                // Image info section
                Section {
                    imageInfoCard
                }
                
                // Tab content
                switch selectedTab {
                case 0: styleSectionContent
                case 1: canvasSectionContent
                case 2: exportSectionContent
                default: styleSectionContent
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
    
    // MARK: - Image Info Card
    private var imageInfoCard: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Image(nsImage: viewModel.originalImage)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("screenshot")
                    .font(.system(size: 13, weight: .semibold))
                
                Text("\(Int(viewModel.originalImage.size.width)) × \(Int(viewModel.originalImage.size.height)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Zoom indicator
            Text("\(Int(viewModel.config.zoom))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2), in: Capsule())
        }
    }
    
    // MARK: - Style Section
    @ViewBuilder
    private var styleSectionContent: some View {
        // Mockup Style
        Section("mockup") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
                ForEach(MockupStyle.allCases) { style in
                    mockupStyleButton(style)
                }
            }
            
            if viewModel.config.showMockup && viewModel.config.mockupStyle != .defaultStyle && viewModel.config.mockupStyle != .outline {
                LabeledContent("border") {
                    Slider(value: $viewModel.config.mockupBorderSize, in: 0...10, step: 0.5)
                        .frame(width: 120)
                    Text("\(viewModel.config.mockupBorderSize, specifier: "%.1f")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28)
                }
            }
        }
        
        // Corner Radius
        Section("corners") {
            Picker("Style", selection: $viewModel.config.borderStyle) {
                ForEach(BorderStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: viewModel.config.borderStyle) { _, newValue in
                viewModel.config.borderRadius = newValue.cornerRadius
            }
            
            LabeledContent("radius") {
                Slider(value: $viewModel.config.borderRadius, in: 0...40)
                    .frame(width: 120)
                Text("\(Int(viewModel.config.borderRadius))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28)
            }
        }
        
        // Transform
        Section("transform") {
            LabeledContent("rotation") {
                HStack(spacing: 4) {
                    Button { viewModel.config.rotation -= 90 } label: {
                        Image(systemName: "rotate.left")
                    }
                    .buttonStyle(.bordered)
                    
                    Text("\(Int(viewModel.config.rotation))°")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 36)
                    
                    Button { viewModel.config.rotation += 90 } label: {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    // MARK: - Canvas Section (Background & Layout)
    @ViewBuilder
    private var canvasSectionContent: some View {
        // Background Type
        Section("background") {
            // Type picker with icons
            HStack(spacing: 2) {
                ForEach(BackgroundType.allCases) { type in
                    backgroundTypeButton(type)
                }
            }
            .padding(3)
            .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            
            // Background content
            backgroundContent
        }
        
        // Layout
        Section("layout") {
            LabeledContent("padding") {
                Slider(value: $viewModel.config.padding, in: 0...200, step: 8)
                    .frame(width: 100)
                Text("\(Int(viewModel.config.padding))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28)
            }
            LabeledContent("scale") {
                Slider(value: $viewModel.config.imageScale, in: 10...200, step: 5)
                    .frame(width: 100)
                Text("\(Int(viewModel.config.imageScale))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36)
            }
        }
        
        // Social Presets
        if viewModel.config.selectedSocialPreset != nil {
            Section("export.size") {
                if let preset = viewModel.config.selectedSocialPreset {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(preset.platform) — \(preset.name)")
                                .font(.system(size: 12, weight: .medium))
                            Text("\(preset.width) × \(preset.height)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            viewModel.config.selectedSocialPreset = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        
        // Platform presets
        Section {
            DisclosureGroup {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(SocialMediaPreset.groupedByPlatform.keys.sorted(), id: \.self) { platform in
                        ForEach(SocialMediaPreset.groupedByPlatform[platform] ?? []) { preset in
                            presetButton(preset)
                        }
                    }
                }
            } label: {
                Label("social.presets", systemImage: "rectangle.3.group")
            }
        }
    }
    
    // MARK: - Export Section
    @ViewBuilder
    private var exportSectionContent: some View {
        // Quick Actions
        Section("actions") {
            // Primary action - Copy
            Button {
                if let img = viewModel.copyAction() { onCopy(img) }
            } label: {
                Label("copy.to.clipboard", systemImage: "doc.on.clipboard.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            // Secondary action - Save
            Button {
                viewModel.saveAction()
            } label: {
                Label("save.to.file", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        
        // Reset
        Section {
            Button(role: .destructive) {
                viewModel.resetPosition()
            } label: {
                Label("reset.position", systemImage: "arrow.counterclockwise")
            }
        }
    }
    
    // MARK: - Background Content
    @ViewBuilder
    private var backgroundContent: some View {
        switch viewModel.config.backgroundType {
        case .transparent:
            Label("transparent", systemImage: "checkerboard.rectangle")
                .foregroundStyle(.secondary)
            
        case .color:
            colorPickerGrid
            
        case .gradient:
            gradientEditor
            
        case .image:
            wallpaperPicker
        }
    }
    
    // MARK: - Color Picker Grid
    private var colorPickerGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 6)], spacing: 6) {
            ForEach(MagicPreset.presets) { preset in
                let isSelected = viewModel.config.selectedMagicPreset?.id == preset.id
                Button {
                    viewModel.config.selectedMagicPreset = preset
                    viewModel.config.selectedGradient = nil
                    viewModel.config.selectedSolidColor = nil
                    viewModel.config.backgroundImageURL = nil
                } label: {
                    Circle()
                        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? .white : .clear, lineWidth: 2)
                        )
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Gradient Editor
    private var gradientEditor: some View {
        VStack(spacing: 14) {
            // Style picker
            HStack(spacing: 2) {
                ForEach(MeshGradientStyle.allCases) { style in
                    let isSelected = viewModel.config.meshGradientConfig.style == style
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.config.meshGradientConfig.style = style
                        }
                    } label: {
                        Text(style.displayName)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if isSelected {
                                    Capsule().fill(Color.accentColor)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.gray.opacity(0.2), in: Capsule())
            
            // Color pickers
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    let binding: Binding<Color> = {
                        switch index {
                        case 0: return $viewModel.config.meshGradientConfig.color1
                        case 1: return $viewModel.config.meshGradientConfig.color2
                        case 2: return $viewModel.config.meshGradientConfig.color3
                        default: return $viewModel.config.meshGradientConfig.color4
                        }
                    }()
                    
                    ColorPicker("", selection: binding)
                        .labelsHidden()
                        .scaleEffect(1.2)
                        .frame(width: 36, height: 32)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        viewModel.randomizeMeshGradient()
                    }
                } label: {
                    Image(systemName: "dice.fill")
                }
                .buttonStyle(.bordered)
                .help("Randomize")
            }
            
            // Effects
            VStack(spacing: 8) {
                LabeledContent("blur") {
                    Slider(value: $viewModel.config.meshGradientConfig.blurAmount, in: 0...150)
                        .frame(width: 100)
                }
                LabeledContent("grain") {
                    Slider(value: $viewModel.config.meshGradientConfig.noiseAmount, in: 0...100)
                        .frame(width: 100)
                }
                LabeledContent("saturation") {
                    Slider(value: $viewModel.config.meshGradientConfig.saturation, in: 0...200)
                        .frame(width: 100)
                }
                LabeledContent("brightness") {
                    Slider(value: $viewModel.config.meshGradientConfig.brightness, in: 50...150)
                        .frame(width: 100)
                }
            }
            
            // Presets
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                ForEach(MeshGradientPreset.presets) { preset in
                    gradientPresetButton(preset)
                }
            }
        }
    }
    
    // MARK: - Wallpaper Picker
    private var wallpaperPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                viewModel.importCustomImage()
            } label: {
                Label("import.image", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            if viewModel.wallpaperImages.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("loading.wallpapers")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                Text("wallpapers.count \(viewModel.wallpaperImages.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 6)], spacing: 6) {
                    ForEach(viewModel.wallpaperImages, id: \.url) { item in
                        wallpaperButton(item)
                    }
                }
            }
        }
    }
    
    // MARK: - Canvas View
    private var canvasView: some View {
        GeometryReader { geo in
            ZStack {
                // Liquid Glass background - rectangle shape
                Color.clear
                    .glassEffect(.regular, in: .rect)
                
                // Screenshot canvas
                ScreenshotPreviewCanvas(
                    image: viewModel.originalImage,
                    config: viewModel.config,
                    isDragging: $isDraggingScreenshot
                ) { newOffset in
                    viewModel.config.screenshotOffset = newOffset
                }
                .id("canvas-\(viewModel.config.showMockup)-\(viewModel.config.mockupStyle.rawValue)")
                .scaleEffect(viewModel.config.zoom / 100)
                .rotationEffect(.degrees(viewModel.config.rotation))
                .position(
                    x: geo.size.width / 2 + viewModel.offset.width + viewModel.lastOffset.width,
                    y: geo.size.height / 2 + viewModel.offset.height + viewModel.lastOffset.height
                )
            }
            .contentShape(Rectangle())
            .simultaneousGesture(isDraggingScreenshot ? nil : dragGesture)
            .simultaneousGesture(magnifyGesture)
            .onAppear {
                viewModel.canvasSize = geo.size
                viewModel.calculateFitZoom()
            }
            .onChange(of: geo.size) { _, new in
                let oldOffset = viewModel.offset
                let oldLastOffset = viewModel.lastOffset
                viewModel.canvasSize = new
                viewModel.calculateFitZoom()
                viewModel.offset = oldOffset
                viewModel.lastOffset = oldLastOffset
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Component Builders
    
    private func mockupStyleButton(_ style: MockupStyle) -> some View {
        let isSelected = viewModel.config.mockupStyle == style
        return Button {
            viewModel.config.mockupStyle = style
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(style.gradient)
                    .frame(height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? .white : .white.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)
                    )
                
                Text(style.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func backgroundTypeButton(_ type: BackgroundType) -> some View {
        let isSelected = viewModel.config.backgroundType == type
        return Button {
            viewModel.config.backgroundType = type
        } label: {
            Image(systemName: type.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor)
                    }
                }
        }
        .buttonStyle(.plain)
    }
    
    private func presetButton(_ preset: SocialMediaPreset) -> some View {
        let isSelected = viewModel.config.selectedSocialPreset?.id == preset.id
        return Button {
            viewModel.config.selectedSocialPreset = isSelected ? nil : preset
        } label: {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15))
                    .aspectRatio(preset.aspectRatio, contentMode: .fit)
                    .frame(height: 24)
                
                Text(preset.name)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
    
    private func gradientPresetButton(_ preset: MeshGradientPreset) -> some View {
        let isSelected = viewModel.config.selectedMeshPreset?.id == preset.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                let effects = viewModel.config.meshGradientConfig
                viewModel.config.meshGradientConfig = preset.config
                viewModel.config.meshGradientConfig.blurAmount = effects.blurAmount
                viewModel.config.meshGradientConfig.noiseAmount = effects.noiseAmount
                viewModel.config.meshGradientConfig.saturation = effects.saturation
                viewModel.config.meshGradientConfig.brightness = effects.brightness
                viewModel.config.selectedMeshPreset = preset
            }
        } label: {
            preset.config.gradientView(size: CGSize(width: 48, height: 32))
                .frame(width: 48, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? .white : .white.opacity(0.15), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func wallpaperButton(_ item: (url: URL, image: NSImage)) -> some View {
        let isSelected = viewModel.selectedWallpaperURL == item.url
        return Button {
            viewModel.selectedWallpaperURL = item.url
            viewModel.config.backgroundImageURL = item.url
            viewModel.config.selectedMagicPreset = nil
            viewModel.config.selectedGradient = nil
            viewModel.config.selectedSolidColor = nil
        } label: {
            Image(nsImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? .white : .white.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Gestures
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.offset = value.translation
            }
            .onEnded { value in
                viewModel.lastOffset.width += value.translation.width
                viewModel.lastOffset.height += value.translation.height
                viewModel.offset = .zero
            }
    }
    
    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newZoom = viewModel.config.zoom * value
                viewModel.config.zoom = min(max(newZoom, 10), 300)
            }
    }
}



