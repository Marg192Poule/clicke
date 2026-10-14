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
struct EditorHistory {
    private(set) var undoStack: [EditorSnapshot] = []
    private(set) var redoStack: [EditorSnapshot] = []
    /// State before the transaction in progress.
    private var pendingStart: EditorSnapshot?

    private let limit = 60

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
        return true
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
