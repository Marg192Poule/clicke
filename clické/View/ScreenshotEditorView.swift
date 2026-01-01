import SwiftUI
import AppKit
import AVFoundation
internal import UniformTypeIdentifiers

struct ScreenshotEditorView: View {
    let originalImage: NSImage
    let onCopy: (NSImage) -> Void
    let onClose: () -> Void
    
    @StateObject private var viewModel: ScreenshotEditorViewModel
    @State private var selectedBackgroundTab: BackgroundType = .color
    @State private var selectedSidebarTab: SidebarTab = .mockup
    @State private var isDraggingScreenshot: Bool = false
    
    enum SidebarTab { case mockup, frame, text, redact, settings }
    
    init(originalImage: NSImage, onCopy: @escaping (NSImage) -> Void, onClose: @escaping () -> Void) {
        self.originalImage = originalImage
        self.onCopy = onCopy
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: ScreenshotEditorViewModel(originalImage: originalImage))
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Full-bleed canvas behind everything
            centerCanvas
                .ignoresSafeArea()
            
            // Floating sidebar on top (higher z-index)
            HStack(alignment: .top) {
                // Left floating sidebar - flush to top
                leftSidebar
                    .frame(width: 320)
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 12)
                
                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadWallpapers()
            viewModel.calculateFitZoom()
        }
    }
    
    
    // MARK: - Left Sidebar (Floating macOS style)
    private var leftSidebar: some View {
        VStack(spacing: 0) {
            // Window controls (traffic lights) + tabs header
            HStack(spacing: 8) {
                // Traffic light buttons
                HStack(spacing: 6) {
                    windowControlButton(color: Color(nsColor: .systemRed)) {
                        onClose()
                    }
                    windowControlButton(color: Color(nsColor: .systemYellow)) {
                        // Minimize - not available for floating panel
                    }
                    windowControlButton(color: Color(nsColor: .systemGreen)) {
                        // Zoom - not available for floating panel
                    }
                }
                
                Spacer()
                
                // Segmented control for tabs
                Picker("", selection: $selectedSidebarTab) {
                    Image(systemName: "square.on.square").tag(SidebarTab.mockup)
                    Image(systemName: "macwindow").tag(SidebarTab.frame)
                    Image(systemName: "textformat").tag(SidebarTab.text)
                    Image(systemName: "eye.slash").tag(SidebarTab.redact)
                    Image(systemName: "slider.horizontal.3").tag(SidebarTab.settings)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
            
            // Native List
            List {
                // Screenshot info section
                Section {
                    HStack(spacing: 12) {
                        Image(nsImage: viewModel.originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshot")
                                .font(.system(size: 13, weight: .medium))
                            Text("\(Int(viewModel.originalImage.size.width))×\(Int(viewModel.originalImage.size.height))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                switch selectedSidebarTab {
                case .mockup:
                    mockupListContent
                case .frame:
                    frameListContent
                case .text:
                    textListContent
                case .redact:
                    redactListContent
                case .settings:
                    settingsListContent
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
    
    private func windowControlButton(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Mockup List Content (Native macOS)
    @ViewBuilder
    private var mockupListContent: some View {
        Section("Style") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 8) {
                ForEach(MockupStyle.allCases) { style in
                    Button { viewModel.config.mockupStyle = style } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(styleGradient(style))
                                .frame(height: 36)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.ultraThinMaterial.opacity(viewModel.config.mockupStyle == style ? 0 : 0.3))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(viewModel.config.mockupStyle == style ? Color.accentColor : Color.white.opacity(0.1), lineWidth: viewModel.config.mockupStyle == style ? 2 : 1)
                                }
                                .shadow(color: viewModel.config.mockupStyle == style ? Color.accentColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                            Text(style.displayName)
                                .font(.system(size: 9))
                                .foregroundColor(viewModel.config.mockupStyle == style ? .primary : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.glass)
                }
            }
            
            if viewModel.config.showMockup && viewModel.config.mockupStyle != .defaultStyle && viewModel.config.mockupStyle != .outline {
                HStack {
                    Text("Taille du contour")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Slider(value: $viewModel.config.mockupBorderSize, in: 0...10, step: 0.5)
                        .frame(maxWidth: 120)
                    Text(String(format: "%.1f", viewModel.config.mockupBorderSize))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 36)
                }
                .padding(.vertical, 4)
            }
        }
        
        Section("Border") {
            Picker("Style", selection: $viewModel.config.borderStyle) {
                ForEach(BorderStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.config.borderStyle) { _, newValue in
                viewModel.config.borderRadius = newValue.cornerRadius
            }
            
            HStack {
                Text("Radius")
                Slider(value: $viewModel.config.borderRadius, in: 0...40)
                    .frame(maxWidth: 120)
                Text("\(Int(viewModel.config.borderRadius))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
        }
        
        Section("Shadow") {
            Picker("Style", selection: $viewModel.config.shadowStyle) {
                ForEach(ShadowStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            
            if viewModel.config.shadowStyle != .none {
                HStack {
                    Text("Opacity")
                    Slider(value: $viewModel.config.shadowOpacity, in: 0...100)
                        .frame(maxWidth: 120)
                    Text("\(Int(viewModel.config.shadowOpacity))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                }
            }
        }
        
        Section("Transform") {
            HStack {
                Text("Rotation")
                Spacer()
                HStack(spacing: 6) {
                    Button { viewModel.config.rotation -= 90 } label: {
                        Image(systemName: "rotate.left")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    
                    Text("\(Int(viewModel.config.rotation))°")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 36)
                    
                    Button { viewModel.config.rotation += 90 } label: {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                }
            }
            
            HStack {
                Text("Position")
                Spacer()
                Button {
                    viewModel.resetPosition()
                } label: {
                    Text("Reset")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
        }
    }
    
    // MARK: - Frame List Content (Native macOS)
    @ViewBuilder
    private var frameListContent: some View {
        Section("Device Frames") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach([DeviceFrame.macWindow, .browser], id: \.self) { frame in
                    let isSelected = viewModel.config.deviceFrame == frame && viewModel.config.showDeviceFrame
                    Button {
                        viewModel.config.deviceFrame = frame
                        viewModel.config.showDeviceFrame = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: frameIcon(frame))
                                .font(.system(size: 18))
                                .frame(height: 24)
                            Text(frameName(frame))
                                .font(.system(size: 10))
                        }
                        .foregroundColor(isSelected ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.accentColor.opacity(0.4))
                                    }
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                }
                        }
                        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.glass)
                }
            }
            
            Toggle("Show Frame", isOn: $viewModel.config.showDeviceFrame)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
        
        // Export Format info
        if let preset = viewModel.config.selectedSocialPreset {
            Section("Export Format") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(preset.platform) - \(preset.name)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(preset.width) × \(preset.height) px")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.config.selectedSocialPreset = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.vertical, 4)
            }
        }
        
        // Social Media Presets
        ForEach(Array(SocialMediaPreset.groupedByPlatform.keys.sorted()), id: \.self) { platform in
            Section(platform) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(SocialMediaPreset.groupedByPlatform[platform] ?? []) { preset in
                        let isSelected = viewModel.config.selectedSocialPreset?.id == preset.id
                        Button {
                            if isSelected {
                                viewModel.config.selectedSocialPreset = nil
                            } else {
                                viewModel.config.selectedSocialPreset = preset
                            }
                        } label: {
                            VStack(spacing: 4) {
                                // Aspect ratio preview
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2))
                                    .aspectRatio(preset.aspectRatio, contentMode: .fit)
                                    .frame(height: 40)
                                    .overlay {
                                        Image(systemName: socialIcon(platform))
                                            .font(.system(size: 14))
                                            .foregroundColor(isSelected ? .accentColor : .secondary)
                                    }
                                
                                Text(preset.name)
                                    .font(.system(size: 10, weight: .medium))
                                Text(preset.ratio)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(isSelected ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }
    
    private func socialIcon(_ platform: String) -> String {
        switch platform {
        case "Twitter": return "bird"
        case "YouTube": return "play.rectangle.fill"
        case "Instagram": return "camera"
        case "Pinterest": return "pin"
        case "Dribbble": return "basketball"
        case "LinkedIn": return "person.crop.rectangle"
        default: return "rectangle"
        }
    }
    
    private func frameIcon(_ frame: DeviceFrame) -> String {
        switch frame {
        case .none: return "rectangle.slash"
        case .macWindow: return "macwindow"
        case .browser: return "globe"
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .macbook: return "laptopcomputer"
        case .imac: return "desktopcomputer"
        }
    }
    
    private func frameName(_ frame: DeviceFrame) -> String {
        switch frame {
        case .none: return "None"
        case .macWindow: return "macOS"
        case .browser: return "Browser"
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .macbook: return "MacBook"
        case .imac: return "iMac"
        }
    }
    
    private func styleGradient(_ style: MockupStyle) -> LinearGradient {
        switch style {
        case .defaultStyle: return LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        case .glassLight: return LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        case .glassDark: return LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        case .liquidGlass: return LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .insetLight: return LinearGradient(colors: [.gray.opacity(0.2), .gray.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        case .insetDark: return LinearGradient(colors: [.black.opacity(0.4), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        case .outline: return LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
        case .border: return LinearGradient(colors: [.gray.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
    }
    
    // MARK: - Text List Content
    @ViewBuilder
    private var textListContent: some View {
        Section("Add Text") {
            TextField("Enter text...", text: $viewModel.newTextContent)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("Size")
                Slider(value: $viewModel.newTextFontSize, in: 8...64, step: 1)
                    .frame(maxWidth: 120)
                Text("\(Int(viewModel.newTextFontSize))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
            
            ColorPicker("Color", selection: $viewModel.newTextColor)
            
            Button {
                viewModel.addTextOverlay()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Text")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.glass)
            .disabled(viewModel.newTextContent.isEmpty)
        }
        
        if !viewModel.config.textOverlays.isEmpty {
            Section("Text Layers") {
                ForEach(viewModel.config.textOverlays) { overlay in
                    HStack {
                        Text(overlay.text)
                            .lineLimit(1)
                            .foregroundColor(overlay.color)
                        
                        Spacer()
                        
                        Button {
                            viewModel.toggleTextBlur(overlay.id)
                        } label: {
                            Image(systemName: overlay.isBlurred ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(overlay.isBlurred ? .orange : .secondary)
                        }
                        .buttonStyle(.glass)
                        
                        Button {
                            viewModel.removeTextOverlay(overlay.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - Redact List Content
    @ViewBuilder
    private var redactListContent: some View {
        Section("Redact Mode") {
            Toggle("Enable Redact Mode", isOn: $viewModel.config.redactEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
            
            if viewModel.config.redactEnabled {
                Text("Click and drag on the image to blur sensitive areas")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.vertical, 4)
            }
        }
        
        Section("Redact Style") {
            ForEach(RedactStyle.allCases) { style in
                let isSelected = viewModel.config.redactStyle == style
                Button {
                    viewModel.config.redactStyle = style
                } label: {
                    HStack {
                        Image(systemName: redactStyleIcon(style))
                            .foregroundColor(redactStyleColor(style))
                        Text(style.displayName)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? redactStyleColor(style) : Color.white.opacity(0.1), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.glass)
            }
        }
        
        if !viewModel.config.redactRegions.isEmpty {
            Section("Redacted Areas (\(viewModel.config.redactRegions.count))") {
                ForEach(viewModel.config.redactRegions) { region in
                    HStack {
                        Image(systemName: redactStyleIcon(region.style))
                            .foregroundColor(redactStyleColor(region.style))
                        Text("Region \(viewModel.config.redactRegions.firstIndex(where: { $0.id == region.id })! + 1)")
                        Spacer()
                        Button {
                            viewModel.config.redactRegions.removeAll { $0.id == region.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.glass)
                    }
                }
                
                Button {
                    viewModel.config.redactRegions.removeAll()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All")
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.glass)
            }
        }
    }
    
    
    private func redactStyleIcon(_ style: RedactStyle) -> String {
        switch style {
        case .blur: return "aqi.medium"
        case .pixelate: return "square.dashed"
        case .blackBar: return "rectangle.fill"
        }
    }
    
    private func redactStyleColor(_ style: RedactStyle) -> Color {
        switch style {
        case .blur: return .purple
        case .pixelate: return .orange
        case .blackBar: return .gray
        }
    }
    
    @ViewBuilder
    private func redactRegionOverlay(_ region: RedactRegion) -> some View {
        let screenRect = viewModel.imageToScreenCoordinates(region.rect)
        
        Group {
            switch region.style {
            case .blur:
                ZStack {
                    // Solid background to actually hide content
                    Rectangle()
                        .fill(Color.gray.opacity(0.85))
                    // Blur effect on top
                    Rectangle()
                        .fill(.regularMaterial)
                }
            case .pixelate:
                ZStack {
                    // Solid background
                    Rectangle()
                        .fill(Color.gray.opacity(0.9))
                    // Pixelate pattern on top
                    PixelateOverlayView()
                }
            case .blackBar:
                Rectangle()
                    .fill(Color.black)
            }
        }
        .frame(width: screenRect.width, height: screenRect.height)
        .position(x: screenRect.midX, y: screenRect.midY)
    }
    
    // MARK: - Center Canvas
    private var centerCanvas: some View {
        GeometryReader { geo in
            ZStack {
                // Glass effect background with dark tint
                ZStack {
                    Color.black.opacity(0.6)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
                .ignoresSafeArea()
                
                // Centered screenshot - using position for true center in available space
                ScreenshotPreviewCanvas(image: viewModel.originalImage, config: viewModel.config, isDragging: $isDraggingScreenshot) { newOffset in
                    viewModel.config.screenshotOffset = newOffset
                }
                    // ID based on properties that affect canvas size/structure, not visual background
                    .id("canvas-\(viewModel.config.showDeviceFrame)-\(viewModel.config.deviceFrame.rawValue)-\(viewModel.config.showMockup)-\(viewModel.config.mockupStyle.rawValue)-\(viewModel.config.padding)-\(viewModel.config.imageScale)-\(viewModel.config.selectedSocialPreset?.id.uuidString ?? "none")")
                    .scaleEffect(viewModel.config.zoom / 100)
                    .rotationEffect(.degrees(viewModel.config.rotation))
                    .position(
                        x: (320 + 24) + (geo.size.width - 320 - 24) / 2 + viewModel.offset.width + viewModel.lastOffset.width,
                        y: geo.size.height / 2 + viewModel.offset.height + viewModel.lastOffset.height
                    )
                
                // Existing redact regions (displayed in screen space)
                ForEach(viewModel.config.redactRegions) { region in
                    redactRegionOverlay(region)
                }
                
                // Redact drawing overlay (current drawing)
                if viewModel.config.redactEnabled, let start = viewModel.currentRedactStart, let end = viewModel.currentRedactEnd {
                    Rectangle()
                        .fill(redactStyleColor(viewModel.config.redactStyle).opacity(0.3))
                        .frame(
                            width: abs(end.x - start.x),
                            height: abs(end.y - start.y)
                        )
                        .position(
                            x: min(start.x, end.x) + abs(end.x - start.x) / 2,
                            y: min(start.y, end.y) + abs(end.y - start.y) / 2
                        )
                        .overlay {
                            Rectangle()
                                .stroke(redactStyleColor(viewModel.config.redactStyle), style: StrokeStyle(lineWidth: 2, dash: [5]))
                                .frame(
                                    width: abs(end.x - start.x),
                                    height: abs(end.y - start.y)
                                )
                                .position(
                                    x: min(start.x, end.x) + abs(end.x - start.x) / 2,
                                    y: min(start.y, end.y) + abs(end.y - start.y) / 2
                                )
                        }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(viewModel.config.redactEnabled ? redactDragGesture : nil)
            .simultaneousGesture(viewModel.config.redactEnabled || isDraggingScreenshot ? nil : dragGesture)
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
                // Restore offset after zoom recalculation
                viewModel.offset = oldOffset
                viewModel.lastOffset = oldLastOffset
            }
        }
    }
    
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
    
    private var redactDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if viewModel.currentRedactStart == nil {
                    viewModel.currentRedactStart = value.startLocation
                }
                viewModel.currentRedactEnd = value.location
            }
            .onEnded { value in
                if let start = viewModel.currentRedactStart, let end = viewModel.currentRedactEnd {
                    // Store screen coordinates for overlay display
                    let screenRect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: abs(end.x - start.x),
                        height: abs(end.y - start.y)
                    )
                    
                    if screenRect.width > 10 && screenRect.height > 10 {
                        // Convert screen coordinates to image-relative coordinates
                        let imageRect = viewModel.screenToImageCoordinates(screenRect)
                        let region = RedactRegion(rect: imageRect, style: viewModel.config.redactStyle)
                        viewModel.addRedactRegion(region)
                    }
                }
                viewModel.currentRedactStart = nil
                viewModel.currentRedactEnd = nil
            }
    }
    
    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newZoom = viewModel.config.zoom * value
                viewModel.config.zoom = min(max(newZoom, 10), 300)
            }
    }
    
    // MARK: - Settings List Content
    @ViewBuilder
    private var settingsListContent: some View {
                Section("View Zoom") {
                    VStack(spacing: 4) {
                        HStack {
                            Slider(value: $viewModel.config.zoom, in: 10...300, step: 5)
                            .frame(maxWidth: 120)
                            Text("\(Int(viewModel.config.zoom))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 36)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Button("Center") { viewModel.resetPosition() }
                        .buttonStyle(.glass)
                        Button("Fit") { viewModel.fitAndCenter() }
                        .buttonStyle(.glass)
                    }
                }
                
                Section("Image Scale") {
                    VStack(spacing: 4) {
                        HStack {
                        Slider(value: Binding(
                            get: { viewModel.config.imageScale },
                            set: { newValue in
                                viewModel.config.imageScale = newValue
                            }
                        ), in: 10...200, step: 5)
                            .frame(maxWidth: 120)
                            Text("\(Int(viewModel.config.imageScale))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 36)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Button("100%") { viewModel.config.imageScale = 100 }
                        .buttonStyle(.glass)
                        Button("Fit") { viewModel.config.imageScale = 80 }
                        .buttonStyle(.glass)
                }
            }
            
            Section("Screenshot Position") {
                Button("Reset Position") {
                    viewModel.resetScreenshotOffset()
                }
                .buttonStyle(.glass)
            }
                
                Section("Padding") {
                    HStack {
                        Slider(value: $viewModel.config.padding, in: 0...200, step: 8)
                    .frame(maxWidth: 120)
                        Text("\(Int(viewModel.config.padding))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 28)
                    }
                }
                
                Section("Background") {
                    Picker("Type", selection: $selectedBackgroundTab) {
                        ForEach(BackgroundType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedBackgroundTab) { _, newValue in
                        viewModel.config.backgroundType = newValue
                    }
                    
                    backgroundListContent
                }
                
                Section("Background Effects") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Noise")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.none) {
                                    viewModel.config.backgroundNoise = 0
                                }
                            } label: {
                                Text("Off")
                                    .font(.system(size: 10, weight: viewModel.config.backgroundNoise == 0 ? .semibold : .regular))
                                    .foregroundColor(viewModel.config.backgroundNoise == 0 ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.config.backgroundNoise == 0 ? Color.accentColor.opacity(0.3) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(viewModel.config.backgroundNoise == 0 ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.glass)
                            
                            Button {
                                withAnimation(.none) {
                                    viewModel.config.backgroundNoise = 30
                                }
                            } label: {
                                Text("Low")
                                    .font(.system(size: 10, weight: viewModel.config.backgroundNoise == 30 ? .semibold : .regular))
                                    .foregroundColor(viewModel.config.backgroundNoise == 30 ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.config.backgroundNoise == 30 ? Color.accentColor.opacity(0.3) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(viewModel.config.backgroundNoise == 30 ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.glass)
                            
                            Button {
                                withAnimation(.none) {
                                    viewModel.config.backgroundNoise = 70
                                }
                            } label: {
                                Text("High")
                                    .font(.system(size: 10, weight: viewModel.config.backgroundNoise == 70 ? .semibold : .regular))
                                    .foregroundColor(viewModel.config.backgroundNoise == 70 ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.config.backgroundNoise == 70 ? Color.accentColor.opacity(0.3) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(viewModel.config.backgroundNoise == 70 ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.glass)
                        }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Blur")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.none) {
                                    viewModel.config.backgroundBlur = 0
                                }
                            } label: {
                                Text("Off")
                                    .font(.system(size: 10, weight: viewModel.config.backgroundBlur == 0 ? .semibold : .regular))
                                    .foregroundColor(viewModel.config.backgroundBlur == 0 ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.config.backgroundBlur == 0 ? Color.accentColor.opacity(0.3) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(viewModel.config.backgroundBlur == 0 ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.glass)
                            
                            Button {
                                withAnimation(.none) {
                                    viewModel.config.backgroundBlur = 30
                                }
                            } label: {
                                Text("Low")
                                    .font(.system(size: 10, weight: viewModel.config.backgroundBlur == 30 ? .semibold : .regular))
                                    .foregroundColor(viewModel.config.backgroundBlur == 30 ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.config.backgroundBlur == 30 ? Color.accentColor.opacity(0.3) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(viewModel.config.backgroundBlur == 30 ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.glass)
                            
                            Button {
                                withAnimation(.none) {
                                    viewModel.config.backgroundBlur = 70
                                }
                            } label: {
                                Text("High")
                                    .font(.system(size: 10, weight: viewModel.config.backgroundBlur == 70 ? .semibold : .regular))
                                    .foregroundColor(viewModel.config.backgroundBlur == 70 ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.config.backgroundBlur == 70 ? Color.accentColor.opacity(0.3) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(viewModel.config.backgroundBlur == 70 ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    }
                }
                
                Section("Shadow Scene") {
                    Picker("Mode", selection: $viewModel.config.shadowSceneMode) {
                        ForEach(ShadowSceneMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opacity")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack {
                        Slider(value: $viewModel.config.shadowSceneOpacity, in: 0...100, step: 1)
                            .frame(maxWidth: 120)
                            Text("\(Int(viewModel.config.shadowSceneOpacity))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 28)
                        }
                    }
                }
            
            Section {
            VStack(spacing: 10) {
                Button(action: {
                    if let img = viewModel.copyAction() {
                        onCopy(img)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("Copy to Clipboard")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.accentColor.opacity(0.5))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            }
                        }
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.glass)
                    
                    Button(action: {
                        viewModel.saveAction()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save to File")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
            }
                .padding(.vertical, 8)
        }
    }
    
    // Background content for List
    @ViewBuilder
    private var backgroundListContent: some View {
        switch selectedBackgroundTab {
        case .transparent:
            Text("Transparent background")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
        case .color:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28))], spacing: 6) {
                ForEach(MagicPreset.presets) { preset in
                    Button {
                        viewModel.config.selectedMagicPreset = preset
                        viewModel.config.selectedGradient = nil
                        viewModel.config.selectedSolidColor = nil
                        viewModel.config.backgroundImageURL = nil
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(viewModel.config.selectedMagicPreset?.id == preset.id ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.glass)
                }
            }
            
        case .image:
            if viewModel.wallpaperImages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 6) {
                    ForEach(viewModel.wallpaperImages.prefix(12), id: \.url) { item in
                        Button {
                            viewModel.selectedWallpaperURL = item.url
                            viewModel.config.backgroundImageURL = item.url
                            viewModel.config.selectedMagicPreset = nil
                            viewModel.config.selectedGradient = nil
                            viewModel.config.selectedSolidColor = nil
                        } label: {
                            Image(nsImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 35)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(viewModel.selectedWallpaperURL == item.url ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }
    
    private func presetButton(colors: [Color], selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if colors.count == 1 {
                    RoundedRectangle(cornerRadius: 6).fill(colors[0])
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .frame(height: 34)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.white : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.glass)
    }
    
}

// MARK: - Pixelate Overlay View
struct PixelateOverlayView: View {
    var body: some View {
        Canvas { context, size in
            let pixelSize: CGFloat = 10
            let cols = Int(size.width / pixelSize) + 1
            let rows = Int(size.height / pixelSize) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    // Random gray values for pixelated effect
                    let grayValue = Double.random(in: 0.3...0.7)
                    let rect = CGRect(
                        x: CGFloat(col) * pixelSize,
                        y: CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(
                        Rectangle().path(in: rect),
                        with: .color(Color(white: grayValue))
                    )
                }
            }
        }
    }
}

// MARK: - Style Extensions
extension Text {
    func sectionTitleStyle() -> some View {
        self.font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.4))
            .tracking(1)
    }
}

extension Button {
    func smallButtonStyle() -> some View {
        self.font(.system(size: 10))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
    }
}



