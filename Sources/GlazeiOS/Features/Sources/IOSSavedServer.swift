import GlazeCore
import SwiftUI

/// One saved server, whatever it speaks.
///
/// The two connection stores keep their own shapes because a DSM login and a WebDAV
/// address are not the same thing. A list of servers should not care — it shows a
/// name, what it speaks, and where it points, the way every file app does.
enum IOSSavedServer: Identifiable {
    case synology(SynologyConnection)
    case webDAV(WebDAVConnection)

    var id: String {
        switch self {
        case .synology(let connection): "synology:\(connection.id)"
        case .webDAV(let connection): "webdav:\(connection.id)"
        }
    }

    var name: String {
        switch self {
        case .synology(let connection): connection.name
        case .webDAV(let connection): connection.name
        }
    }

    var kind: IOSServerKind {
        switch self {
        case .synology: .synology
        case .webDAV: .webDAV
        }
    }

    /// The account and folder, so two entries for the same box are told apart.
    var detail: String {
        switch self {
        case .synology(let connection):
            "\(connection.account) · \(connection.libraryPath ?? "/")"
        case .webDAV(let connection):
            connection.rootURL.absoluteString
        }
    }
}

/// What Glaze can speak to. Listed rather than assumed, so the add screen and the
/// server list cannot disagree about what exists.
enum IOSServerKind: String, CaseIterable, Identifiable {
    case synology
    case webDAV
    case dlna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .synology: "Synology"
        case .webDAV: "WebDAV"
        case .dlna: "UPnP / DLNA"
        }
    }

    var symbol: String {
        switch self {
        case .synology: "externaldrive.connected.to.line.below"
        case .webDAV: "externaldrive"
        case .dlna: "antenna.radiowaves.left.and.right"
        }
    }

    var detail: String {
        switch self {
        case .synology: L10n.string("ios.server.synology.detail")
        case .webDAV: L10n.string("ios.server.webdav.detail")
        case .dlna: L10n.string("ios.server.dlna.detail")
        }
    }
}
