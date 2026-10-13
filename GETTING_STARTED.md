# Getting Started with AuGenda

## Prerequisites
- macOS 14+
- Xcode 16+
- Apple Developer account (for device testing and distribution)

## Setup

1. Clone the repo
2. Open `AuGenda.xcodeproj` in Xcode
3. Set your team ID in Signing & Capabilities
4. Configure Google OAuth (optional):
   - Create an iOS OAuth client in Google Cloud Console
   - Set `AUGENDA_GOOGLE_CLIENT_ID` in Xcode Build Settings → User-Defined
5. Build and run on iOS Simulator (uses Apple system typography; no custom font binaries required)

## Persistence Architecture
AuGenda is strictly local-first and file-backed via SwiftData (`AppContainer.makePersistentLocalStartupState()`).
There is zero CloudKit sync configured or enabled. UI tests launch with an in-memory container via `-ui-testing`.

## AI Providers (Optional)
AI enrichment is off by default. To enable:
- Go to Settings → AI Enrichment
- Select a provider and enter your API key (stored securely in Keychain)
- Or enable "Local AI only" for zero-cost on-device Apple Intelligence or self-hosted Ollama
