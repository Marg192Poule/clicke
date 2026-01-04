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
                        Button {
                            viewModel.zoomIn()
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .help("Zoom In")
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button {
                            viewModel.zoomOut()
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .help("Zoom Out")
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button {
                            viewModel.resetPosition()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset Disposition")
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Spacer()
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        ShareLink(item: viewModel.getShareableImage(), preview: SharePreview("Screenshot", image: viewModel.getShareableImage())) {
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
            // Navigation toolbar at top
            navigationToolbar
            
            Form {
                switch selectedTab {
                case 0: 
                    appearanceSectionContent
                case 1: 
                    backgroundSectionContent
                case 2: 
                    layoutSectionContent
                default: 
                    appearanceSectionContent
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
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
                    .symbolVariant(.none)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
    
    
    // MARK: - Appearance Section (Tab 0)
    @ViewBuilder
    private var appearanceSectionContent: some View {
        // Mockup Style
        Section("mockup") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
                ForEach(MockupStyle.allCases) { style in
                    mockupStyleButton(style)
                }
            }
            
            if viewModel.config.showMockup && viewModel.config.mockupStyle != .defaultStyle && viewModel.config.mockupStyle != .outline {
                LabeledContent("border") {
                    SliderWithDefaultCGFloat(
                        value: $viewModel.config.mockupBorderSize,
                        range: 0...10,
                        defaultValue: 3,
                        step: 0.5,
                        showValue: true,
                        decimals: 1
                    )
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
                SliderWithDefaultCGFloat(
                    value: $viewModel.config.borderRadius,
                    range: 0...40,
                    defaultValue: 20,
                    showValue: true
                )
            }
        }
        
        // Transform
        Section("transform") {
            // Scale
            LabeledContent("scale") {
                SliderWithDefaultCGFloat(
                    value: $viewModel.config.scale,
                    range: 0.1...3.0,
                    defaultValue: 1.0,
                    showValue: true,
                    decimals: 2
                )
            }
            
            // Rotation Z (2D)
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
            
            // Rotation X (3D)
            LabeledContent("rotation.x") {
                HStack(spacing: 4) {
                    SliderWithDefault(
                        value: $viewModel.config.rotationX,
                        range: -90...90,
                        defaultValue: 0,
                        showValue: true,
                        unit: "°"
                    )
                    Button {
                        viewModel.config.rotationX = 0
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .help("Reset")
                }
            }
            
            // Rotation Y (3D)
            LabeledContent("rotation.y") {
                HStack(spacing: 4) {
                    SliderWithDefault(
                        value: $viewModel.config.rotationY,
                        range: -90...90,
                        defaultValue: 0,
                        showValue: true,
                        unit: "°"
                    )
                    Button {
                        viewModel.config.rotationY = 0
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .help("Reset")
                }
            }
        }
    }
    
    // MARK: - Background Section (Tab 1)
    @ViewBuilder
    private var backgroundSectionContent: some View {
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
        
        // Effects - available for all backgrounds except transparent
        if viewModel.config.backgroundType != .transparent {
            Section("effects") {
                // Blur - unified for all backgrounds
                LabeledContent("blur") {
                    SliderWithDefault(
                        value: $viewModel.config.meshGradientConfig.blurAmount,
                        range: 0...150,
                        defaultValue: 0,
                        showValue: true
                    )
                }
                
                // Saturation
                LabeledContent("saturation") {
                    SliderWithDefault(
                        value: $viewModel.config.meshGradientConfig.saturation,
                        range: 0...200,
                        defaultValue: 100,
                        showValue: true,
                        unit: "%"
                    )
                }
                
                // Brightness
                LabeledContent("brightness") {
                    SliderWithDefault(
                        value: $viewModel.config.meshGradientConfig.brightness,
                        range: 50...150,
                        defaultValue: 100,
                        showValue: true,
                        unit: "%"
                    )
                }
                
                // Noise - unified for all backgrounds
                LabeledContent("noise") {
                    SliderWithDefault(
                        value: $viewModel.config.meshGradientConfig.noiseAmount,
                        range: 0...100,
                        defaultValue: 0,
                        showValue: true
                    )
                }
            }
        }
    }
    
    // MARK: - Layout Section (Tab 2)
    @ViewBuilder
    private var layoutSectionContent: some View {
        // Layout Controls
        Section("layout") {
            LabeledContent("padding") {
                SliderWithDefaultCGFloat(
                    value: $viewModel.config.padding,
                    range: 0...200,
                    defaultValue: 80,
                    showValue: true
                )
            }
            LabeledContent("scale") {
                SliderWithDefaultCGFloat(
                    value: $viewModel.config.imageScale,
                    range: 10...200,
                    defaultValue: 100,
                    showValue: true,
                    unit: "%"
                )
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
    
    // MARK: - Export Section (Tab 3)
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
        } label: {
            VStack(spacing: 4) {
                // Preview with fake screenshot inside
                ZStack {
                    // Background gradient/style
                    RoundedRectangle(cornerRadius: 6)
                        .fill(style.gradient)
                    
                    // Fake screenshot preview (white rounded rectangle)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.9))
                        .padding(6)
                        .overlay(
                            // Fake content lines
                            VStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 2)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 2)
                            }
                            .padding(8)
                        )
                    
                    // Border for outline/border styles
                    if style == .outline || style == .border {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(style == .outline ? .white.opacity(0.5) : .gray.opacity(0.5), lineWidth: style == .outline ? 1 : 2)
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

// MARK: - Slider with Default Indicator (Double version)
struct SliderWithDefault: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    var step: Double? = nil
    var showValue: Bool = false
    var unit: String = ""
    var decimals: Int = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                // Background track
                GeometryReader { geometry in
                    // Default value indicator line
                    let normalizedDefault = (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                    let defaultPosition = geometry.size.width * normalizedDefault
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 2, height: 20)
                        .position(x: defaultPosition, y: geometry.size.height / 2)
                }
                .frame(height: 20)
                
                // Actual slider
                if let step = step {
                    Slider(value: $value, in: range, step: step)
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
            }
        }
    }
    
    private func formatValue(_ val: Double) -> String {
        if decimals > 0 {
            return String(format: "%.\(decimals)f", val)
        } else if unit == "%" {
            return "\(Int(val))"
        } else {
            return String(format: "%.0f", val)
        }
    }
}

// MARK: - Slider with Default Indicator (CGFloat version)
struct SliderWithDefaultCGFloat: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let defaultValue: CGFloat
    var step: CGFloat? = nil
    var showValue: Bool = false
    var unit: String = ""
    var decimals: Int = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                // Background track
                GeometryReader { geometry in
                    // Default value indicator line
                    let normalizedDefault = (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                    let defaultPosition = geometry.size.width * normalizedDefault
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 2, height: 20)
                        .position(x: defaultPosition, y: geometry.size.height / 2)
                }
                .frame(height: 20)
                
                // Actual slider
                if let step = step {
                    Slider(value: $value, in: range, step: step)
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
            }
        }
    }
    
    private func formatValue(_ val: CGFloat) -> String {
        if decimals > 0 {
            return String(format: "%.\(decimals)f", val)
        } else if unit == "%" {
            return "\(Int(val))"
        } else {
            return String(format: "%.0f", val)
        }
    }
}




