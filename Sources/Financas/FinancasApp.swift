import SwiftUI
#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
#else
import UIKit
private typealias PlatformColor = UIColor
#endif

enum AppBrand {
    static let accent = adaptive(light: PlatformColor(red: 0.035, green: 0.38, blue: 0.26, alpha: 1), dark: PlatformColor(red: 0.48, green: 0.77, blue: 0.59, alpha: 1))
    static let evergreen = Color(red: 0.035, green: 0.38, blue: 0.26)
    static let forest = Color(red: 0.055, green: 0.19, blue: 0.16)
    static let mint = Color(red: 0.76, green: 0.91, blue: 0.64)
    static let amber = adaptive(light: PlatformColor(red: 0.66, green: 0.36, blue: 0.12, alpha: 1), dark: PlatformColor(red: 0.91, green: 0.68, blue: 0.39, alpha: 1))
    static let canvas = adaptive(light: PlatformColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1), dark: PlatformColor(red: 0.10, green: 0.13, blue: 0.12, alpha: 1))
    static let surface = adaptive(light: PlatformColor(red: 1, green: 0.995, blue: 0.98, alpha: 1), dark: PlatformColor(red: 0.15, green: 0.18, blue: 0.17, alpha: 1))
    private static func adaptive(light: PlatformColor, dark: PlatformColor) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
        #else
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
        #endif
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

#if os(macOS)
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
#endif

private struct LaunchScreenView<Content: View>: View {
    /// Set when the app is opened for a specific task (a widget shortcut): go straight in.
    var skip = false
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            // Mounted as the splash leaves, so the screen's entrance animations play in view.
            if !isShowingSplash {
                content()
                    .transition(.opacity)
            }

            if isShowingSplash {
                SplashView()
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.05))))
                    .zIndex(1)
            }
        }
        #if os(iOS)
        .statusBarHidden(isShowingSplash)
        #endif
        .onChange(of: skip) { _, skip in
            guard skip, isShowingSplash else { return }
            withAnimation(.easeOut(duration: 0.25)) { isShowingSplash = false }
        }
        .task {
            try? await Task.sleep(for: .seconds(skip ? 0 : (reduceMotion ? 1.2 : SplashView.duration + 0.45)))
            guard !Task.isCancelled, SplashView.frozenTime == nil else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 0.45)) {
                isShowingSplash = false
            }
        }
    }
}

#if os(macOS)
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
#else
@main
struct FinancasApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var router = QuickActionRouter()

    var body: some Scene {
        WindowGroup {
            LaunchScreenView(skip: router.pending != nil) {
                ContentView()
            }
            .environmentObject(store)
            .environmentObject(router)
            .tint(AppBrand.accent)
            .onOpenURL { router.open($0) }
        }
    }
}
#endif
