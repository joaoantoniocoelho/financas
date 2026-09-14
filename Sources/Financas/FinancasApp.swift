import AppKit
import SwiftUI

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
                .frame(minWidth: 960, minHeight: 620)
            let hostingController = NSHostingController(rootView: content)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Finanças"
            window.setContentSize(NSSize(width: 1120, height: 720))
            window.minSize = NSSize(width: 960, height: 620)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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

            VStack(spacing: 24) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                Text("Finanças")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

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
        } label: {
            Label("Finanças", systemImage: "creditcard")
        }
        .menuBarExtraStyle(.window)
    }
}
