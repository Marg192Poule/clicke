import Foundation

/// The undoable state of the editor: canvas style + layers (selection, zoom and pan are not undoable).
struct EditorSnapshot: Equatable {
    var config: ScreenshotStyleConfig
    var items: [CanvasItem]
}

/// Snapshot-based undo / redo.
///
/// Changes are coalesced into *transactions*: the state before the first change is remembered,
/// and the transaction is committed when the editing burst ends (a slider or a drag is released,
/// or no change happened for a short moment). Dragging a slider therefore produces one undo step.
///
/// The history is bounded by its number of steps and by the memory of the bitmaps only it keeps
/// alive (each redaction replaces a layer's bitmap, and the previous one stays undoable).
struct EditorHistory {
    private(set) var undoStack: [EditorSnapshot] = []
    private(set) var redoStack: [EditorSnapshot] = []
    /// State before the transaction in progress.
    private var pendingStart: EditorSnapshot?

    private let limit = 60
    private let byteLimit = 512 * 1024 * 1024

    var canUndo: Bool { pendingStart != nil || !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records the state before a change (only the first change of a transaction matters).
    mutating func willChange(from snapshot: EditorSnapshot) {
        if pendingStart == nil {
            pendingStart = snapshot
        }
    }

    /// Ends the transaction in progress. Returns `true` if an undo step was added.
    @discardableResult
    mutating func commit(current: EditorSnapshot) -> Bool {
        guard let start = pendingStart else { return false }
        pendingStart = nil
        guard start != current else { return false }
        undoStack.append(start)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
        trimToByteLimit(current: current)
        return true
    }

    /// Drops the oldest steps while the bitmaps that only the history references exceed `byteLimit`.
    private mutating func trimToByteLimit(current: EditorSnapshot) {
        while !undoStack.isEmpty, retainedBytes(excluding: current) > byteLimit {
            undoStack.removeFirst()
        }
    }

    private func retainedBytes(excluding current: EditorSnapshot) -> Int {
        var seen = Set(current.items.map { ObjectIdentifier($0.image) })
        var bytes = 0
        for snapshot in undoStack + redoStack {
            for item in snapshot.items where seen.insert(ObjectIdentifier(item.image)).inserted {
                bytes += item.image.byteCount
            }
        }
        return bytes
    }

    /// Returns the state to restore, or `nil` if there's nothing to undo.
    mutating func undo(current: EditorSnapshot) -> EditorSnapshot? {
        commit(current: current)
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Returns the state to restore, or `nil` if there's nothing to redo.
    mutating func redo(current: EditorSnapshot) -> EditorSnapshot? {
        commit(current: current)
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
