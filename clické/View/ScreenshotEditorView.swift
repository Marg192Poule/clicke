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
    @State private var isHoveringClose = false
    @State private var isHoveringMinimize = false
    @State private var isHoveringZoom = false
    
    init(originalImage: NSImage, onCopy: @escaping (NSImage) -> Void, onClose: @escaping () -> Void) {
        self.originalImage = originalImage
        self.onCopy = onCopy
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: ScreenshotEditorViewModel(originalImage: originalImage))
    }
    
    var body: some View {
        ZStack {
            // Full-bleed canvas - content layer
            canvasView
                .ignoresSafeArea()
            
            // Floating inspector panel - Liquid Glass layer
            HStack {
                inspectorPanel
                    .frame(width: 300)
                    .padding(16)
                
                Spacer()
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadWallpapers()
            viewModel.calculateFitZoom()
        }
        // Toolbar action handlers
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
    
    // MARK: - Inspector Panel (Liquid Glass)
    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            // Header with window controls
            panelHeader
            
            Divider()
                .opacity(0.4)
            
            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Image info card
                    imageInfoCard
                    
                    // Tab content
                    Group {
                        switch selectedTab {
                        case 0: styleSection
                        case 1: canvasSection
                        case 2: exportSection
                        default: styleSection
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                .padding(16)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 15)
    }
    
    // MARK: - Panel Header
    private var panelHeader: some View {
        HStack(spacing: 10) {
            // Traffic lights
            HStack(spacing: 8) {
                trafficLightButton(color: .red, hoverColor: Color(red: 1, green: 0.4, blue: 0.4), isHovering: $isHoveringClose) {
                    onClose()
                }
                trafficLightButton(color: .yellow, hoverColor: Color(red: 1, green: 0.85, blue: 0.4), isHovering: $isHoveringMinimize) {}
                trafficLightButton(color: .green, hoverColor: Color(red: 0.4, green: 0.9, blue: 0.4), isHovering: $isHoveringZoom) {}
            }
            
            Spacer()
            
            // Tab selector - native segmented
            Picker("", selection: $selectedTab.animation(.easeInOut(duration: 0.2))) {
                Text("Style").tag(0)
                Text("Canvas").tag(1)
                Text("Export").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                Text("Screenshot")
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
        .padding(12)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Style Section
    private var styleSection: some View {
        VStack(spacing: 20) {
            // Mockup Style
            controlGroup("Mockup") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
                    ForEach(MockupStyle.allCases) { style in
                        mockupStyleButton(style)
                    }
                }
                
                if viewModel.config.showMockup && viewModel.config.mockupStyle != .defaultStyle && viewModel.config.mockupStyle != .outline {
                    labeledSlider("Border", value: $viewModel.config.mockupBorderSize, range: 0...10, step: 0.5)
                }
            }
            
            // Corner Radius
            controlGroup("Corners") {
                Picker("", selection: $viewModel.config.borderStyle) {
                    ForEach(BorderStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewModel.config.borderStyle) { _, newValue in
                    viewModel.config.borderRadius = newValue.cornerRadius
                }
                
                labeledSlider("Radius", value: $viewModel.config.borderRadius, range: 0...40)
            }
            
            // Transform
            controlGroup("Transform") {
                HStack {
                    Text("Rotation")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Button { viewModel.config.rotation -= 90 } label: {
                            Image(systemName: "rotate.left")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 28)
                                .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        
                        Text("\(Int(viewModel.config.rotation))°")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 36)
                        
                        Button { viewModel.config.rotation += 90 } label: {
                            Image(systemName: "rotate.right")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 28)
                                .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Canvas Section (Background & Layout)
    private var canvasSection: some View {
        VStack(spacing: 20) {
            // Background Type
            controlGroup("Background") {
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
            controlGroup("Layout") {
                labeledSlider("Padding", value: $viewModel.config.padding, range: 0...200, step: 8)
                labeledSlider("Scale", value: $viewModel.config.imageScale, range: 10...200, step: 5, suffix: "%")
            }
            
            // Social Presets (collapsed by default)
            if viewModel.config.selectedSocialPreset != nil {
                controlGroup("Export Size") {
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
            DisclosureGroup {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(SocialMediaPreset.groupedByPlatform.keys.sorted(), id: \.self) { platform in
                        ForEach(SocialMediaPreset.groupedByPlatform[platform] ?? []) { preset in
                            presetButton(preset)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11))
                    Text("Social Presets")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
    }
    
    // MARK: - Export Section
    private var exportSection: some View {
        VStack(spacing: 20) {
            // Quick Actions
            controlGroup("Actions") {
                // Primary action - Copy
                Button {
                    if let img = viewModel.copyAction() { onCopy(img) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 14))
                        Text("Copy to Clipboard")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
                
                // Secondary action - Save
                Button {
                    viewModel.saveAction()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                        Text("Save to File")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            
            // Reset
            controlGroup("Reset") {
                Button {
                    viewModel.resetPosition()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                        Text("Reset Position")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Background Content
    @ViewBuilder
    private var backgroundContent: some View {
        switch viewModel.config.backgroundType {
        case .transparent:
            HStack(spacing: 8) {
                Image(systemName: "checkerboard.rectangle")
                    .foregroundStyle(.tertiary)
                Text("Transparent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Randomize")
            }
            
            // Effects
            VStack(spacing: 6) {
                effectSlider("Blur", icon: "drop.fill", value: $viewModel.config.meshGradientConfig.blurAmount, range: 0...150)
                effectSlider("Grain", icon: "sparkles", value: $viewModel.config.meshGradientConfig.noiseAmount, range: 0...100)
                effectSlider("Saturation", icon: "circle.lefthalf.filled", value: $viewModel.config.meshGradientConfig.saturation, range: 0...200)
                effectSlider("Brightness", icon: "sun.max.fill", value: $viewModel.config.meshGradientConfig.brightness, range: 50...150)
            }
            .padding(10)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            
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
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("Import Image")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            
            if viewModel.wallpaperImages.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading wallpapers…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                Text("\(viewModel.wallpaperImages.count) wallpapers")
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
                // Background with subtle material
                Color.black.opacity(0.7)
                Rectangle().fill(.ultraThinMaterial.opacity(0.3))
                
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
                    x: 316 + (geo.size.width - 316) / 2 + viewModel.offset.width + viewModel.lastOffset.width,
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
    }
    
    // MARK: - Component Builders
    
    private func controlGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            
            content()
        }
    }
    
    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, suffix: String = "") -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Slider(value: value, in: range, step: step)
                .tint(Color.accentColor)
            
            Text("\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }
    
    private func labeledSlider(_ label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat = 1, suffix: String = "") -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Slider(value: value, in: range, step: step)
                .tint(Color.accentColor)
            
            Text("\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }
    
    private func effectSlider(_ label: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Slider(value: value, in: range)
                .tint(Color.accentColor)
            
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
        }
    }
    
    private func trafficLightButton(color: Color, hoverColor: Color, isHovering: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(isHovering.wrappedValue ? hoverColor : color.opacity(0.8))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .onHover { isHovering.wrappedValue = $0 }
    }
    
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



