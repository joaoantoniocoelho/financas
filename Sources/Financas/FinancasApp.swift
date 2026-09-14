import AppKit
import SwiftUI

enum AppBrand {
    static let accent = adaptive(light: NSColor(red: 0.035, green: 0.38, blue: 0.26, alpha: 1), dark: NSColor(red: 0.48, green: 0.77, blue: 0.59, alpha: 1))
    static let evergreen = Color(red: 0.035, green: 0.38, blue: 0.26)
    static let forest = Color(red: 0.055, green: 0.19, blue: 0.16)
    static let mint = Color(red: 0.76, green: 0.91, blue: 0.64)
    static let amber = adaptive(light: NSColor(red: 0.66, green: 0.36, blue: 0.12, alpha: 1), dark: NSColor(red: 0.91, green: 0.68, blue: 0.39, alpha: 1))
    static let canvas = adaptive(light: NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1), dark: NSColor(red: 0.10, green: 0.13, blue: 0.12, alpha: 1))
    static let surface = adaptive(light: NSColor(red: 1, green: 0.995, blue: 0.98, alpha: 1), dark: NSColor(red: 0.15, green: 0.18, blue: 0.17, alpha: 1))
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let chartColors: [Color] = [
        accent,
        Color(red: 0.15, green: 0.43, blue: 0.72),
        Color(red: 0.51, green: 0.32, blue: 0.68),
        Color(red: 0.84, green: 0.49, blue: 0.12),
        Color(red: 0.78, green: 0.28, blue: 0.31),
        Color(red: 0.08, green: 0.53, blue: 0.56)
    ]
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    private let mainWindow = MainWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func showMainWindow() {
        mainWindow.show(store: store)
    }
}

@MainActor
final class MainWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var controller: NSWindowController?

    func show(store: AppStore) {
        if controller == nil {
            let content = LaunchScreenView {
                ContentView()
            }
                .environmentObject(store)
                .tint(AppBrand.accent)
                .frame(minWidth: 960, minHeight: 620)
            let hostingController = NSHostingController(rootView: content)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Finanças"
            window.setContentSize(NSSize(width: 1120, height: 720))
            window.minSize = NSSize(width: 960, height: 620)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("FinancasMainWindow")
            window.center()
            window.delegate = self
            controller = NSWindowController(window: window)
        }

        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private struct LaunchScreenView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            content()
                .opacity(isShowingSplash ? 0 : 1)

            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.25))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.32)) {
                isShowingSplash = false
            }
        }
    }
}

private struct SplashView: View {
    @State private var iconScale: CGFloat = 0.88
    @State private var iconOpacity = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.12, blue: 0.085),
                    Color(red: 0.015, green: 0.23, blue: 0.155),
                    Color(red: 0.01, green: 0.15, blue: 0.105)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 18) {
                BrandMark()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                Text("Finanças").font(.system(size: 38, weight: .semibold, design: .serif)).foregroundStyle(.white)
                Text("Mais clareza. Mais possibilidades.").foregroundStyle(AppBrand.mint)

                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.88))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                iconScale = 1
                iconOpacity = 1
            }
        }
    }
}

@main
struct FinancasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView {
                appDelegate.showMainWindow()
            }
            .environmentObject(appDelegate.store)
            .tint(AppBrand.accent)
        } label: {
            Image(nsImage: AppBrand.menuBarIcon)
                .accessibilityLabel("Finanças")
        }
        .menuBarExtraStyle(.window)
    }
}
