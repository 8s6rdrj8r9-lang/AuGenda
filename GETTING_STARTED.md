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
5. Add font files to the Xcode target (see `AuGenda/Fonts/README.md`)
6. Build and run on iOS Simulator

## CloudKit (Optional)
CloudKit is disabled by default. To enable:
1. Register `iCloud.com.augenda.AuGenda` in Apple Developer Portal
2. Change `AppContainer.dev` to `AppContainer.production` in `AuGendaApp.swift`
3. Add `CloudKit` capability to the app target

## AI Providers (Optional)
AI enrichment is off by default. To enable:
- Go to Settings → AI Enrichment
- Select a provider and enter your API key
- Or enable "Local AI only" for zero-cost Ollama
