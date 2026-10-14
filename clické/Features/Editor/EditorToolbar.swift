import AppKit
import Observation

/// The editor window's toolbar: undo/redo, zoom, add image, redact, save, copy, inspector.
///
/// A native `NSToolbar` (rather than SwiftUI's bridged `.toolbar`) because each bridged item is a
/// separate SwiftUI host, which roughly doubled the time to open the editor. Adjacent items share
/// a Liquid Glass group; spaces separate the groups. Item states follow the model through Observation.
final class EditorToolbarController: NSObject, NSToolbarDelegate {
    private let model: ScreenshotEditorViewModel
    let toolbar: NSToolbar
    /// The window whose subtitle shows the export size.
    weak var window: NSWindow? {
        didSet { update() }
    }

    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let zoomMenu = NSMenu()

    init(model: ScreenshotEditorViewModel) {
        self.model = model
        self.toolbar = NSToolbar(identifier: "ClickeEditorToolbar")
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [.zoomOut, .zoomLevel, .zoomIn]
        buildZoomMenu()
        observeModel()
    }

    // MARK: - NSToolbarDelegate

    private static let itemOrder: [NSToolbarItem.Identifier] = [
        .undo, .redo,
        .flexibleSpace,
        .zoomOut, .zoomLevel, .zoomIn,
        .flexibleSpace,
        .addImage, .redact,
        .space,
        .save, .copy,
        .space,
        .inspector,
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemOrder
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemOrder
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item: NSToolbarItem
        switch identifier {
        case .undo:
            item = button(identifier, String(localized: "Undo"), symbol: "arrow.uturn.backward", help: String(localized: "Undo (⌘Z)"), action: #selector(undo))
        case .redo:
            item = button(identifier, String(localized: "Redo"), symbol: "arrow.uturn.forward", help: String(localized: "Redo (⇧⌘Z)"), action: #selector(redo))
        case .zoomOut:
            item = button(identifier, String(localized: "Zoom Out"), symbol: "minus.magnifyingglass", help: String(localized: "Zoom out (⌘−)"), action: #selector(zoomOut))
        case .zoomIn:
            item = button(identifier, String(localized: "Zoom In"), symbol: "plus.magnifyingglass", help: String(localized: "Zoom in (⌘+)"), action: #selector(zoomIn))
        case .zoomLevel:
            let menuItem = NSMenuToolbarItem(itemIdentifier: identifier)
            menuItem.menu = zoomMenu
            menuItem.showsIndicator = false
            menuItem.label = String(localized: "Zoom")
            menuItem.toolTip = String(localized: "Choose a zoom level")
            item = menuItem
        case .addImage:
            item = button(identifier, String(localized: "Add Image"), symbol: "photo.badge.plus", help: String(localized: "Add an image as a new layer"), action: #selector(addImage))
        case .redact:
            item = button(identifier, String(localized: "Redact"), symbol: "eye.slash", help: String(localized: "Hide sensitive information in the selected image"), action: #selector(redact))
        case .save:
            item = button(identifier, String(localized: "Save"), symbol: "square.and.arrow.down", help: String(localized: "Save the image (⌘S)"), action: #selector(save))
        case .copy:
            item = button(identifier, String(localized: "Copy"), symbol: "doc.on.doc", help: String(localized: "Copy the image to the clipboard (⌘C)"), action: #selector(copyImage))
        case .inspector:
            item = button(identifier, String(localized: "Inspector"), symbol: "sidebar.right", help: String(localized: "Show or hide the inspector (⌥⌘I)"), action: #selector(toggleInspector))
        default:
            return nil
        }
        items[identifier] = item
        update()
        return item
    }

    private func button(_ identifier: NSToolbarItem.Identifier, _ label: String, symbol: String, help: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = help
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.autovalidates = false
        item.target = self
        item.action = action
        return item
    }

    // MARK: - Zoom Menu

    private func buildZoomMenu() {
        zoomMenu.addItem(withTitle: String(localized: "Zoom to Fit"), action: #selector(zoomToFit), keyEquivalent: "")
        zoomMenu.addItem(withTitle: String(localized: "Actual Size"), action: #selector(actualSize), keyEquivalent: "")
        zoomMenu.addItem(.separator())
        for percent in [25, 50, 100, 200, 400] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(zoomToPreset(_:)), keyEquivalent: "")
            item.tag = percent
            zoomMenu.addItem(item)
        }
        for item in zoomMenu.items {
            item.target = self
        }
    }

    // MARK: - State

    /// Re-applies the model state to the items, then tracks the next change.
    private func observeModel() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeModel() }
        }
    }

    private func update() {
        let canUndo = model.canUndo
        let canRedo = model.canRedo
        let canExport = !model.isExporting && !model.items.isEmpty
        let zoom = "\(model.zoomPercentage)%"

        items[.undo]?.isEnabled = canUndo
        items[.redo]?.isEnabled = canRedo
        items[.save]?.isEnabled = canExport
        items[.copy]?.isEnabled = canExport
        items[.redact]?.isEnabled = !model.items.isEmpty
        if let zoomItem = items[.zoomLevel], zoomItem.title != zoom {
            zoomItem.title = zoom
        }
        let size = model.geometry.pixelSizeDescription
        if let window, window.subtitle != size {
            window.subtitle = size
        }
    }

    // MARK: - Actions

    @objc private func undo() { model.undo() }
    @objc private func redo() { model.redo() }
    @objc private func zoomOut() { model.zoomOut() }
    @objc private func zoomIn() { model.zoomIn() }
    @objc private func zoomToFit() { model.zoomToFit() }
    @objc private func actualSize() { model.zoomToActualSize() }
    @objc private func zoomToPreset(_ sender: NSMenuItem) { model.setZoom(CGFloat(sender.tag) / 100, anchor: nil, animated: true) }
    @objc private func addImage() { model.addImagesFromFile() }
    @objc private func redact() { model.redactSelectedLayer() }
    @objc private func save() { model.save() }
    @objc private func copyImage() { model.copyToClipboard() }
    @objc private func toggleInspector() { model.toggleInspector() }
}

private extension NSToolbarItem.Identifier {
    static let undo = Self("Undo")
    static let redo = Self("Redo")
    static let zoomOut = Self("ZoomOut")
    static let zoomLevel = Self("ZoomLevel")
    static let zoomIn = Self("ZoomIn")
    static let addImage = Self("AddImage")
    static let redact = Self("Redact")
    static let save = Self("Save")
    static let copy = Self("Copy")
    static let inspector = Self("Inspector")
}
