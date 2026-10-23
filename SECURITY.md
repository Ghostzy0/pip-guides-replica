# Security

This experimental app handles screenshots which can contain sensitive information. It does not include a cloud client or telemetry. Guide files and exports are not encrypted. Pause before private details and review every image before sharing. Solid redaction removes pixels in app-saved copies; old exports and external backups remain independent.

To report a security concern, use the maintainer's GitHub security reporting route if enabled, or contact the verified GitHub maintainer without posting sensitive data. Do not put passwords, private screenshots or exploit data in a public issue. No response-time commitment is made. The current version is an alpha and has no commercial support guarantee.

Trust boundary: imported files are size/schema/image checked; HTML output escapes text and restricts resource loading. ScreenCaptureKit scope is one selected window. Typed keys are never monitored. AX secure-field checks are best effort for controls exposed by macOS, not a guarantee for every app.
