/// OmniDebugLink remote-debugging client SDK for Flutter.
///
/// Usage:
/// ```dart
/// OmniDebugLink.bootstrap( // or call start() yourself after runApp
///   url: 'wss://api.omnidebuglink.dev/ws?token=<clientToken>',
///   app: const MyApp(),
/// );
/// ```
library omnidebuglink;

export 'src/omni_debug_link.dart'
    show
        OmniDebugLink,
        LinkState,
        OmniDebugLinkTaskRequest,
        OmniDebugLinkTaskHandler,
        OmniDebugLinkTaskRegistry,
        OmniDebugLinkTaskException;
