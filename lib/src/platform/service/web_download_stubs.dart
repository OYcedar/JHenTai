/// Stub implementations for download services on web.
/// On web, all download operations are delegated to the backend server
/// via the BackendApiClient. These stubs exist so the app can compile
/// for web without importing dart:io-dependent service code.
///
/// The web UI pages for downloads call BackendApiClient directly
/// instead of going through these services.

class WebGalleryDownloadServiceStub {}

class WebArchiveDownloadServiceStub {}

class WebLocalGalleryServiceStub {}
