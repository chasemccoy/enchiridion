import EnchiridionKit
import Foundation

/// Where a model's fetch stands.
///
/// It describes the last request only: what it loaded stays in the model when a later refresh fails, so a view shows
/// its content whenever there is some and falls back to this state (spinner, error, not allowed) when there is none.
public enum LoadState: Equatable, Sendable {
    /// Nothing asked yet.
    case idle
    case loading
    case loaded
    case failed(EnchiridionError)

    public var isLoading: Bool { self == .loading }

    public var error: EnchiridionError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// Where a create or edit stands: the record editor and the share card.
public enum SaveState: Equatable, Sendable {
    case editing
    case saving
    /// The record as the server stored it.
    case saved(Record)
    /// Nothing was saved, or nothing could be confirmed (the models' `mayHaveSaved` tells which); `save()` again
    /// retries.
    case failed(EnchiridionError)

    public var isSaving: Bool { self == .saving }

    public var savedRecord: Record? {
        if case .saved(let record) = self { return record }
        return nil
    }

    public var error: EnchiridionError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// What a model did to a record, for the others that show it (the library's rows, an open detail).
public enum RecordChange: Equatable, Sendable {
    case created(Record)
    case updated(Record)
    case deleted(id: Int)
    /// Found deleted elsewhere: a detail's load or curate answered 404. As `.deleted`, and the library, which outlives
    /// the detail that found it, says so in its alert.
    case vanished(id: Int)
}

/// Receives the changes a detail or editor model makes.
public typealias RecordChangeHandler = @MainActor (RecordChange) -> Void

extension EnchiridionError {
    /// What a failed call means for the UI, or nil when it was cancelled (a superseded search, a closed screen), which
    /// shows nothing. The client throws only `EnchiridionError` and `CancellationError`; anything else reads as
    /// unreachable.
    static func classify(_ error: any Error) -> EnchiridionError? {
        EnchiridionError.fromTransport(error) as? EnchiridionError
    }

    /// A failure after which a create may still have landed: the request may have reached the server and only the
    /// answer was lost (a timeout, a dropped connection, the API restarting mid-request).
    var mightHaveLanded: Bool {
        switch self {
        case .unreachable, .restarting: true
        default: false
        }
    }

    /// A failure after which a write certainly didn't happen: the request never left (Tailscale off, offline), or
    /// the server answered and refused it. Not `decoding`: a 2xx whose body couldn't be read did land.
    var neverLanded: Bool {
        switch self {
        case .tailscaleOff, .offline, .unauthorized, .forbidden, .notFound, .rejected, .server: true
        case .unreachable, .restarting, .decoding: false
        }
    }
}
