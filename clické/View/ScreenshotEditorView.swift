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
                
                // Segmented control for tabs - more native style
                HStack(spacing: 2) {
                    ForEach([
                        (SidebarTab.mockup, "square.on.square", "Style"),
                        (SidebarTab.frame, "macwindow", "Frame"),
                        (SidebarTab.text, "textformat", "Text"),
                        (SidebarTab.redact, "eye.slash", "Redact"),
                        (SidebarTab.settings, "slider.horizontal.3", "Settings")
                    ], id: \.0) { tab, icon, name in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedSidebarTab = tab
                            }
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: selectedSidebarTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedSidebarTab == tab ? .primary : .secondary)
                                .frame(width: 32, height: 24)
                                .background {
                                    if selectedSidebarTab == tab {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.gray.opacity(0.2))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
                .padding(3)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.gray.opacity(0.15))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Divider()
                .opacity(0.5)
            
            // Native List with proper styling
            ScrollView {
                VStack(spacing: 0) {
                    // Screenshot info section - compact header
                    HStack(spacing: 10) {
                        Image(nsImage: viewModel.originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshot")
                                .font(.system(size: 12, weight: .medium))
                            Text("\(Int(viewModel.originalImage.size.width)) × \(Int(viewModel.originalImage.size.height))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    
                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.3)
                    
                    // Tab content
                    VStack(spacing: 0) {
                        switch selectedSidebarTab {
                        case .mockup:
                            mockupTabContent
                        case .frame:
                            frameTabContent
                        case .text:
                            textTabContent
                        case .redact:
                            redactTabContent
                        case .settings:
                            settingsTabContent
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
            .scrollIndicators(.hidden)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
    
    // MARK: - Tab Contents (Native styling without List)
    @ViewBuilder
    private var mockupTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Style Section
            sectionHeader("Style")
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
                    .buttonStyle(.plain)
                }
            }
            
            if viewModel.config.showMockup && viewModel.config.mockupStyle != .defaultStyle && viewModel.config.mockupStyle != .outline {
                sliderRow(label: "Border", value: $viewModel.config.mockupBorderSize, range: 0...10, step: 0.5)
            }
            
            Divider().opacity(0.3)
            
            // Border Section
            sectionHeader("Border")
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
            
            sliderRow(label: "Radius", value: $viewModel.config.borderRadius, range: 0...40)
            
            Divider().opacity(0.3)
            
            // Shadow Section
            sectionHeader("Shadow")
            Picker("", selection: $viewModel.config.shadowStyle) {
                ForEach(ShadowStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            if viewModel.config.shadowStyle != .none {
                sliderRow(label: "Opacity", value: $viewModel.config.shadowOpacity, range: 0...100)
            }
            
            Divider().opacity(0.3)
            
            // Transform Section
            sectionHeader("Transform")
            HStack {
                Text("Rotation")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Button { viewModel.config.rotation -= 90 } label: {
                        Image(systemName: "rotate.left")
                            .font(.system(size: 11))
                            .frame(width: 26, height: 26)
                            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(Int(viewModel.config.rotation))°")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32)
                    
                    Button { viewModel.config.rotation += 90 } label: {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 11))
                            .frame(width: 26, height: 26)
                            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button {
                viewModel.resetPosition()
            } label: {
                Text("Reset Position")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var frameTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Device Frame")
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
                                .fill(isSelected ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.15))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Toggle("Show Frame", isOn: $viewModel.config.showDeviceFrame)
                .toggleStyle(.switch)
                .font(.system(size: 12))
            
            if let preset = viewModel.config.selectedSocialPreset {
                Divider().opacity(0.3)
                sectionHeader("Export Format")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(preset.platform) - \(preset.name)")
                            .font(.system(size: 11, weight: .medium))
                        Text("\(preset.width) × \(preset.height)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.config.selectedSocialPreset = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider().opacity(0.3)
            
            // Social Media Presets - collapsed sections
            ForEach(Array(SocialMediaPreset.groupedByPlatform.keys.sorted()), id: \.self) { platform in
                DisclosureGroup {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(SocialMediaPreset.groupedByPlatform[platform] ?? []) { preset in
                            let isSelected = viewModel.config.selectedSocialPreset?.id == preset.id
                            Button {
                                viewModel.config.selectedSocialPreset = isSelected ? nil : preset
                            } label: {
                                VStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2))
                                        .aspectRatio(preset.aspectRatio, contentMode: .fit)
                                        .frame(height: 28)
                                    Text(preset.name)
                                        .font(.system(size: 9))
                                        .foregroundColor(isSelected ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: socialIcon(platform))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(platform)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .tint(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var textTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Add Text")
            
            TextField("Enter text...", text: $viewModel.newTextContent)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            
            sliderRow(label: "Size", value: $viewModel.newTextFontSize, range: 8...64, step: 1)
            
            HStack {
                Text("Color")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                ColorPicker("", selection: $viewModel.newTextColor)
                    .labelsHidden()
            }
            
            Button {
                viewModel.addTextOverlay()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Text")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.newTextContent.isEmpty)
            .opacity(viewModel.newTextContent.isEmpty ? 0.5 : 1)
            
            if !viewModel.config.textOverlays.isEmpty {
                Divider().opacity(0.3)
                sectionHeader("Text Layers")
                
                ForEach(viewModel.config.textOverlays) { overlay in
                    HStack {
                        Circle()
                            .fill(overlay.color)
                            .frame(width: 10, height: 10)
                        Text(overlay.text)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button {
                            viewModel.toggleTextBlur(overlay.id)
                        } label: {
                            Image(systemName: overlay.isBlurred ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 10))
                                .foregroundColor(overlay.isBlurred ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            viewModel.removeTextOverlay(overlay.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    @ViewBuilder
    private var redactTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Redact Mode")
            
            Toggle("Enable Redact Mode", isOn: $viewModel.config.redactEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 12))
            
            if viewModel.config.redactEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .foregroundColor(.orange)
                    Text("Draw on image to blur areas")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            
            Divider().opacity(0.3)
            sectionHeader("Redact Style")
            
            ForEach(RedactStyle.allCases) { style in
                let isSelected = viewModel.config.redactStyle == style
                Button {
                    viewModel.config.redactStyle = style
                } label: {
                    HStack {
                        Image(systemName: redactStyleIcon(style))
                            .foregroundColor(redactStyleColor(style))
                            .frame(width: 20)
                        Text(style.displayName)
                            .font(.system(size: 11))
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? redactStyleColor(style).opacity(0.15) : Color.gray.opacity(0.1))
                    }
                }
                .buttonStyle(.plain)
            }
            
            if !viewModel.config.redactRegions.isEmpty {
                Divider().opacity(0.3)
                sectionHeader("Redacted Areas (\(viewModel.config.redactRegions.count))")
                
                ForEach(viewModel.config.redactRegions) { region in
                    HStack {
                        Image(systemName: redactStyleIcon(region.style))
                            .font(.system(size: 10))
                            .foregroundColor(redactStyleColor(region.style))
                        Text("Region \((viewModel.config.redactRegions.firstIndex(where: { $0.id == region.id }) ?? 0) + 1)")
                            .font(.system(size: 11))
                        Spacer()
                        Button {
                            viewModel.config.redactRegions.removeAll { $0.id == region.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                
                Button {
                    viewModel.config.redactRegions.removeAll()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private var settingsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // View Zoom
            sectionHeader("View Zoom")
            sliderRow(label: "Zoom", value: $viewModel.config.zoom, range: 10...300, step: 5, suffix: "%")
            
            HStack(spacing: 8) {
                Button("Center") { viewModel.resetPosition() }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                
                Button("Fit") { viewModel.fitAndCenter() }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
            }
            
            Divider().opacity(0.3)
            
            // Image Scale
            sectionHeader("Image Scale")
            sliderRow(label: "Scale", value: $viewModel.config.imageScale, range: 10...200, step: 5, suffix: "%")
            
            Divider().opacity(0.3)
            
            // Padding
            sectionHeader("Padding")
            sliderRow(label: "Size", value: $viewModel.config.padding, range: 0...200, step: 8)
            
            Divider().opacity(0.3)
            
            // Background
            sectionHeader("Background")
            Picker("", selection: $selectedBackgroundTab) {
                ForEach(BackgroundType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedBackgroundTab) { _, newValue in
                viewModel.config.backgroundType = newValue
            }
            
            backgroundTabContent
            
            Divider().opacity(0.3)
            
            // Effects
            sectionHeader("Effects")
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Noise")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach([(0.0, "Off"), (30.0, "Low"), (70.0, "High")], id: \.0) { value, label in
                        Button {
                            viewModel.config.backgroundNoise = value
                        } label: {
                            Text(label)
                                .font(.system(size: 10, weight: viewModel.config.backgroundNoise == value ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(viewModel.config.backgroundNoise == value ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Blur")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach([(0.0, "Off"), (30.0, "Low"), (70.0, "High")], id: \.0) { value, label in
                        Button {
                            viewModel.config.backgroundBlur = value
                        } label: {
                            Text(label)
                                .font(.system(size: 10, weight: viewModel.config.backgroundBlur == value ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(viewModel.config.backgroundBlur == value ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Divider().opacity(0.3)
            
            // Shadow Scene
            sectionHeader("Shadow Scene")
            Picker("", selection: $viewModel.config.shadowSceneMode) {
                ForEach(ShadowSceneMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            sliderRow(label: "Opacity", value: $viewModel.config.shadowSceneOpacity, range: 0...100)
            
            Divider().opacity(0.3)
            
            // Action Buttons
            VStack(spacing: 10) {
                Button {
                    if let img = viewModel.copyAction() {
                        onCopy(img)
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("Copy to Clipboard")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor)
                    }
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                
                Button {
                    viewModel.saveAction()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save to File")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // Background content for tab
    @ViewBuilder
    private var backgroundTabContent: some View {
        switch selectedBackgroundTab {
        case .transparent:
            HStack(spacing: 8) {
                Image(systemName: "checkerboard.rectangle")
                    .foregroundColor(.secondary)
                Text("Transparent background")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            
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
                            .shadow(color: viewModel.config.selectedMagicPreset?.id == preset.id ? Color.accentColor.opacity(0.4) : .clear, radius: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .image:
            if viewModel.wallpaperImages.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading wallpapers...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(viewModel.wallpaperImages.count) wallpapers")
                        .font(.system(size: 9))
                        .foregroundColor(Color.gray.opacity(0.6))
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 6) {
                        ForEach(viewModel.wallpaperImages, id: \.url) { item in
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
                                    .frame(width: 56, height: 38)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(viewModel.selectedWallpaperURL == item.url ? Color.accentColor : Color.white.opacity(0.1), lineWidth: viewModel.selectedWallpaperURL == item.url ? 2 : 0.5)
                                    )
                                    .shadow(color: viewModel.selectedWallpaperURL == item.url ? Color.accentColor.opacity(0.4) : .clear, radius: 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Views
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }
    
    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.6))
                .frame(width: 36, alignment: .trailing)
        }
    }
    
    private func sliderRow(label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat = 1, suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.6))
                .frame(width: 36, alignment: .trailing)
        }
    }
    
    private func windowControlButton(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
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
                    Rectangle()
                        .fill(Color.gray.opacity(0.85))
                    Rectangle()
                        .fill(.regularMaterial)
                }
            case .pixelate:
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.9))
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
                
                // Centered screenshot
                ScreenshotPreviewCanvas(image: viewModel.originalImage, config: viewModel.config, isDragging: $isDraggingScreenshot) { newOffset in
                    viewModel.config.screenshotOffset = newOffset
                }
                .id("canvas-\(viewModel.config.showDeviceFrame)-\(viewModel.config.deviceFrame.rawValue)-\(viewModel.config.showMockup)-\(viewModel.config.mockupStyle.rawValue)-\(viewModel.config.selectedSocialPreset?.id.uuidString ?? "none")")
                .scaleEffect(viewModel.config.zoom / 100)
                .rotationEffect(.degrees(viewModel.config.rotation))
                .position(
                    x: (320 + 24) + (geo.size.width - 320 - 24) / 2 + viewModel.offset.width + viewModel.lastOffset.width,
                    y: geo.size.height / 2 + viewModel.offset.height + viewModel.lastOffset.height
                )
                
                // Existing redact regions
                ForEach(viewModel.config.redactRegions) { region in
                    redactRegionOverlay(region)
                }
                
                // Redact drawing overlay
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
                    let screenRect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: abs(end.x - start.x),
                        height: abs(end.y - start.y)
                    )
                    
                    if screenRect.width > 10 && screenRect.height > 10 {
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



