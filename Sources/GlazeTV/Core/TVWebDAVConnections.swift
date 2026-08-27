import GlazeCore

/// tvOS keeps the product-specific name at call sites while sharing persistence and
/// keychain behavior with macOS.
typealias TVWebDAVConnections = WebDAVConnectionStore
