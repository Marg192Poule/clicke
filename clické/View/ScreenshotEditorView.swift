import SwiftUI
import AppKit
import AVFoundation
internal import UniformTypeIdentifiers

struct ScreenshotEditorView: View {
    let originalImage: NSImage
    let onCopy: (NSImage) -> Void
    let onClose: () -> Void
    
    @StateObject private var viewModel: ScreenshotEditorViewModel
    @State private var selectedTab: Int = 1
    @State private var isDraggingScreenshot: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var colorPanelObserver: NSObjectProtocol?
    @State private var colorPanelCloseObserver: NSObjectProtocol?
    
    // Cached shareable image state
    @State private var cachedShareableImage: Image?
    @State private var lastRenderHash: Int = 0
    
    init(originalImage: NSImage, onCopy: @escaping (NSImage) -> Void, onClose: @escaping () -> Void) {
        self.originalImage = originalImage
        self.onCopy = onCopy
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: ScreenshotEditorViewModel(originalImage: originalImage))
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            inspectorContent
                .frame(width: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            canvasView
                .toolbar {
                    toolbarContent
                }
        }
        .toolbar(removing: .title)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadWallpapers()
            viewModel.calculateFitZoom()
        }
        .onDisappear {
            cleanupObservers()
        }
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
        .onChange(of: viewModel.config.renderHash) { _, newHash in
            // Invalider le cache de l'image partageable quand la config change
            if lastRenderHash != newHash {
                cachedShareableImage = nil
                lastRenderHash = newHash
            }
        }
    }
    
    // MARK: - Cleanup
    private func cleanupObservers() {
        if let observer = colorPanelObserver {
            NotificationCenter.default.removeObserver(observer)
            colorPanelObserver = nil
        }
        if let observer = colorPanelCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            colorPanelCloseObserver = nil
        }
    }
    
    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
        }
        
        ToolbarItem(placement: .automatic) {
            Button(action: viewModel.zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")
        }
        
        ToolbarItem(placement: .automatic) {
            Button(action: viewModel.zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")
        }
        
        ToolbarItem(placement: .automatic) {
            Button(action: viewModel.resetPosition) {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset Disposition")
        }
        
        ToolbarItem(placement: .automatic) {
            Spacer()
        }
        
        ToolbarItem(placement: .automatic) {
            // Use cached shareable image
            ShareLink(item: shareableImage, preview: SharePreview("Screenshot", image: shareableImage)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
        }
        
        ToolbarItem(placement: .automatic) {
            Button("Copy", systemImage: "doc.on.doc") {
                if let img = viewModel.copyAction() { onCopy(img) }
            }
        }
    }
    
    // Cached shareable image
    private var shareableImage: Image {
        if let cached = cachedShareableImage {
            return cached
        }
        let image = viewModel.getShareableImage()
        DispatchQueue.main.async {
            cachedShareableImage = image
        }
        return image
    }
    
    // MARK: - Inspector Content
    private var inspectorContent: some View {
        VStack(spacing: 0) {
            navigationToolbar
            
            Form {
                switch selectedTab {
                case 0: appearanceSectionContent
                case 1: backgroundSectionContent
                case 2: layoutSectionContent
                default: appearanceSectionContent
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.top, -1)
        }
    }
    
    // MARK: - Navigation Toolbar
    private var navigationToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton(icon: "paintbrush", tag: 0, label: "Appearance")
            toolbarDivider
            toolbarButton(icon: "photo", tag: 1, label: "Background")
            toolbarDivider
            toolbarButton(icon: "square.on.square", tag: 2, label: "Layout")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternarySystemFill)))
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
    
    private func toolbarButton(icon: String, tag: Int, label: String) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 24, height: 24)
                }
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
    
    // MARK: - Appearance Section
    @ViewBuilder
    private var appearanceSectionContent: some View {
        Section("mockup") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(MockupStyle.allCases) { style in
                    mockupStyleButton(style)
                }
            }
            
            if viewModel.config.showMockup && viewModel.config.mockupStyle != .defaultStyle {
                LabeledContent("size") {
                    OptimizedSlider(
                        value: $viewModel.config.mockupBorderSize,
                        range: 0...10,
                        defaultValue: 3,
                        step: 0.5,
                        showValue: true,
                        decimals: 1
                    )
                }
                
                if viewModel.config.mockupStyle == .border {
                    ColorPicker("color", selection: $viewModel.config.borderColor, supportsOpacity: false)
                }
            }
        }
        
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
                OptimizedSlider(
                    value: $viewModel.config.borderRadius,
                    range: 0...40,
                    defaultValue: 20,
                    showValue: true
                )
            }
        }
        
        Section("transform") {
            LabeledContent("scale") {
                OptimizedSlider(
                    value: $viewModel.config.scale,
                    range: 0.1...3.0,
                    defaultValue: 1.0,
                    showValue: true,
                    decimals: 2
                )
            }
            
            LabeledContent("rotation") {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            viewModel.config.rotation -= 90
                        }
                    } label: {
                        Image(systemName: "rotate.left")
                    }
                    .buttonStyle(.bordered)
                    
                    Text("\(Int(viewModel.config.rotation))°")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 36)
                    
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            viewModel.config.rotation += 90
                        }
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if viewModel.config.mockupStyle != .glassEffect {
                LabeledContent("rotation.x") {
                    HStack(spacing: 4) {
                        OptimizedSlider(
                            value: $viewModel.config.rotationX,
                            range: -90...90,
                            defaultValue: 0,
                            showValue: true,
                            unit: "°"
                        )
                        Button { viewModel.config.rotationX = 0 } label: {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .help("Reset")
                    }
                }
                
                LabeledContent("rotation.y") {
                    HStack(spacing: 4) {
                        OptimizedSlider(
                            value: $viewModel.config.rotationY,
                            range: -90...90,
                            defaultValue: 0,
                            showValue: true,
                            unit: "°"
                        )
                        Button { viewModel.config.rotationY = 0 } label: {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .help("Reset")
                    }
                }
            }
        }
    }
    
    // MARK: - Background Section
    @ViewBuilder
    private var backgroundSectionContent: some View {
        Section("background") {
            HStack(spacing: 2) {
                ForEach(BackgroundType.allCases) { type in
                    backgroundTypeButton(type)
                }
            }
            .padding(3)
            .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            
            backgroundContent
        }
        
        if viewModel.config.backgroundType != .transparent {
            Section("effects") {
                LabeledContent("blur") {
                    OptimizedSlider(
                        value: $viewModel.config.gradientConfig.blurAmount,
                        range: 0...80,
                        defaultValue: 0,
                        showValue: true
                    )
                }
                
                LabeledContent("saturation") {
                    OptimizedSlider(
                        value: $viewModel.config.gradientConfig.saturation,
                        range: 0...200,
                        defaultValue: 100,
                        showValue: true,
                        unit: "%"
                    )
                }
                
                LabeledContent("brightness") {
                    OptimizedSlider(
                        value: $viewModel.config.gradientConfig.brightness,
                        range: 50...150,
                        defaultValue: 100,
                        showValue: true,
                        unit: "%"
                    )
                }
                
                LabeledContent("noise") {
                    OptimizedSlider(
                        value: $viewModel.config.gradientConfig.noiseAmount,
                        range: 0...100,
                        defaultValue: 0,
                        showValue: true
                    )
                }
            }
        }
    }
    
    // MARK: - Layout Section
    @ViewBuilder
    private var layoutSectionContent: some View {
        Section("layout") {
            LabeledContent("scale") {
                OptimizedSlider(
                    value: $viewModel.config.imageScale,
                    range: 10...200,
                    defaultValue: 100,
                    showValue: true,
                    unit: "%"
                )
            }
        }
        
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
                        Button { viewModel.config.selectedSocialPreset = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SocialMediaPreset.groupedByPlatform.keys.sorted(), id: \.self) { platform in
                    ForEach(SocialMediaPreset.groupedByPlatform[platform] ?? []) { preset in
                        presetButton(preset)
                    }
                }
            }
        } header: {
            Label("social.presets", systemImage: "rectangle.3.group")
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
    
    // MARK: - Open Native Color Panel
    private func openColorPanel() {
        cleanupObservers()
        
        let colorPanel = NSColorPanel.shared
        
        let currentNSColor: NSColor = viewModel.config.customColor != .clear
            ? NSColor(viewModel.config.customColor)
            : .white
        
        colorPanel.color = currentNSColor
        colorPanel.isContinuous = true
        
        colorPanelObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: colorPanel,
            queue: .main
        ) { _ in
            self.viewModel.config.customColor = Color(nsColor: colorPanel.color)
            
            if self.viewModel.config.customColor != .clear {
                self.viewModel.config.selectedMagicPreset = nil
                self.viewModel.config.selectedGradient = nil
                self.viewModel.config.selectedSolidColor = nil
                self.viewModel.config.backgroundImageURL = nil
            }
        }
        
        colorPanelCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: colorPanel,
            queue: .main
        ) { _ in
            self.cleanupObservers()
        }
        
        colorPanel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Color Picker Grid
    private var colorPickerGrid: some View {
        HStack(spacing: 10) {
            ForEach(MagicPreset.presets) { preset in
                let isSelected = viewModel.config.selectedMagicPreset?.id == preset.id && viewModel.config.customColor == .clear
                Button {
                    viewModel.config.selectedMagicPreset = preset
                    viewModel.config.selectedGradient = nil
                    viewModel.config.selectedSolidColor = nil
                    viewModel.config.backgroundImageURL = nil
                    viewModel.config.customColor = .clear
                } label: {
                    Circle()
                        .fill(preset.colors.first ?? .white)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle().strokeBorder(isSelected ? .white : .white.opacity(0.2), lineWidth: isSelected ? 2.5 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Button(action: openColorPanel) {
                ZStack {
                    Circle()
                        .fill(AngularGradient(
                            stops: [
                                .init(color: .red, location: 0.0),
                                .init(color: .yellow, location: 0.17),
                                .init(color: .green, location: 0.33),
                                .init(color: .cyan, location: 0.5),
                                .init(color: .blue, location: 0.67),
                                .init(color: .purple, location: 0.83),
                                .init(color: .red, location: 1.0)
                            ],
                            center: .center
                        ))
                        .frame(width: 32, height: 32)
                    
                    if viewModel.config.customColor != .clear {
                        Circle()
                            .fill(viewModel.config.customColor)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
                .overlay(
                    Circle().strokeBorder(
                        viewModel.config.customColor != .clear ? .white : .white.opacity(0.2),
                        lineWidth: viewModel.config.customColor != .clear ? 2.5 : 1
                    )
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Gradient Editor
    private var gradientEditor: some View {
        VStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(GradientStyle.allCases) { style in
                    let isSelected = viewModel.config.gradientConfig.style == style
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.config.gradientConfig.style = style
                        }
                    } label: {
                        Text(style.displayName)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background { if isSelected { Capsule().fill(Color.accentColor) } }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.gray.opacity(0.2), in: Capsule())
            
            HStack(spacing: 8) {
                ColorPicker("", selection: $viewModel.config.gradientConfig.color1)
                    .labelsHidden()
                    .scaleEffect(1.2)
                    .frame(width: 36, height: 32)
                
                if viewModel.config.gradientConfig.useThreeColors {
                    ColorPicker("", selection: $viewModel.config.gradientConfig.color2)
                        .labelsHidden()
                        .scaleEffect(1.2)
                        .frame(width: 36, height: 32)
                }
                
                ColorPicker("", selection: $viewModel.config.gradientConfig.color3)
                    .labelsHidden()
                    .scaleEffect(1.2)
                    .frame(width: 36, height: 32)
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.config.gradientConfig.useThreeColors.toggle()
                    }
                } label: {
                    Image(systemName: viewModel.config.gradientConfig.useThreeColors ? "3.circle.fill" : "2.circle.fill")
                }
                .buttonStyle(.bordered)
                .help(viewModel.config.gradientConfig.useThreeColors ? "Use 2 colors" : "Use 3 colors")
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        viewModel.randomizeGradient()
                    }
                } label: {
                    Image(systemName: "dice.fill")
                }
                .buttonStyle(.bordered)
                .help("Randomize")
            }
            
            if viewModel.config.gradientConfig.style == .linear {
                HStack {
                    Image(systemName: "angle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    Slider(value: $viewModel.config.gradientConfig.angle, in: 0...360, step: 15)
                    Text("\(Int(viewModel.config.gradientConfig.angle))°")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                ForEach(SimpleGradientPreset.presets) { preset in
                    gradientPresetButton(preset)
                }
            }
        }
    }
    
    // MARK: - Wallpaper Picker
    private var wallpaperPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: viewModel.importCustomImage) {
                Label("import.image", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            if viewModel.wallpaperImages.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("loading.wallpapers")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 6)], spacing: 6) {
                        ForEach(viewModel.wallpaperImages, id: \.url) { item in
                            wallpaperButton(item)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
    
    // MARK: - Canvas View
    private var canvasView: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear.glassEffect(.regular, in: .rect)
                
                ScreenshotPreviewCanvas(
                    image: viewModel.originalImage,
                    config: viewModel.config,
                    isDragging: $isDraggingScreenshot
                ) { newOffset in
                    viewModel.config.screenshotOffset = newOffset
                }
                .id("canvas-\(viewModel.config.showMockup)-\(viewModel.config.mockupStyle.rawValue)")
                .scaleEffect(viewModel.config.zoom / 100)
                .animation(.easeOut(duration: 0.15), value: viewModel.config.zoom)
                .position(
                    x: geo.size.width / 2 + 150 + viewModel.offset.width + viewModel.lastOffset.width,
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
            if style == .glassEffect {
                viewModel.config.rotationX = 0
                viewModel.config.rotationY = 0
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.9))
                        .padding(style == .defaultStyle ? 4 : 8)
                        .background {
                            if style == .glassEffect {
                                RoundedRectangle(cornerRadius: 4).fill(.ultraThinMaterial).padding(4)
                            } else if style == .border {
                                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.5)).padding(4)
                            }
                        }
                }
                .frame(height: 38)
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
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).fill(Color.accentColor)
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
    
    private func gradientPresetButton(_ preset: SimpleGradientPreset) -> some View {
        let isSelected = viewModel.config.selectedGradientPreset?.id == preset.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                let effects = viewModel.config.gradientConfig
                viewModel.config.gradientConfig = preset.config
                viewModel.config.gradientConfig.blurAmount = effects.blurAmount
                viewModel.config.gradientConfig.noiseAmount = effects.noiseAmount
                viewModel.config.gradientConfig.saturation = effects.saturation
                viewModel.config.gradientConfig.brightness = effects.brightness
                viewModel.config.selectedGradientPreset = preset
            }
        } label: {
            preset.config.previewView(size: CGSize(width: 48, height: 32))
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
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? .white : .white.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
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

// MARK: - Optimized Generic Slider
/// Slider générique optimisé supportant Double et CGFloat
struct OptimizedSlider<T: BinaryFloatingPoint>: View where T.Stride: BinaryFloatingPoint {
    @Binding var value: T
    let range: ClosedRange<T>
    let defaultValue: T
    var step: T? = nil
    var showValue: Bool = false
    var unit: String = ""
    var decimals: Int = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    let normalizedDefault = CGFloat((defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound))
                    let defaultPosition = geometry.size.width * normalizedDefault
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 2, height: 20)
                        .position(x: defaultPosition, y: geometry.size.height / 2)
                }
                .frame(height: 20)
                
                if let step = step {
                    Slider(value: $value, in: range, step: T.Stride(step))
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .frame(width: 100)
            
            if showValue {
                Text(formatValue(value) + unit)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: unit.isEmpty ? 28 : 36, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: Double(value))
            }
        }
    }
    
    private func formatValue(_ val: T) -> String {
        let doubleVal = Double(val)
        if decimals > 0 {
            return String(format: "%.\(decimals)f", doubleVal)
        } else if unit == "%" {
            return "\(Int(doubleVal))"
        } else {
            return String(format: "%.0f", doubleVal)
        }
    }
}
