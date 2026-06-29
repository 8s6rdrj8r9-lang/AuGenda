// ErrorBanner.swift
// AuGenda
//
// Lightweight, non-blocking error banner for surfacing save failures
// and other user-actionable errors without modal interruption.

import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
final class ErrorBannerController: ObservableObject {
    static let shared = ErrorBannerController()
    
    @Published var message: String? = nil
    private var dismissTask: Task<Void, Never>? = nil
    
    func show(_ message: String) {
        self.message = message
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
    
    func dismiss() {
        dismissTask?.cancel()
        message = nil
    }
}

struct ErrorBanner: View {
    @StateObject private var controller = ErrorBannerController.shared
    
    var body: some View {
        VStack {
            if let message = controller.message {
                HStack(spacing: Tokens.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Tokens.Color.warning)
                    Text(message)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextPrimary)
                        .accessibilityHint("Error notification")
                    Spacer()
                    Button { controller.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }
                    .accessibilityLabel("Dismiss error")
                }
                .padding(Tokens.Spacing.base)
                .background(Tokens.Color.warning.opacity(0.1))
                .overlay(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(Tokens.Color.warning),
                    alignment: .top
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Error: \(message)")
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: controller.message)
        .zIndex(100)
        .allowsHitTesting(controller.message != nil)
    }
}
