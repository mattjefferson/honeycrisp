import Foundation
import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(AppKit)
@preconcurrency import AppKit
#endif

enum NotesAccessPrompt {
    static func promptForNotesContainer(defaultRoot: URL) -> String? {
        guard isInteractive else { return nil }
        #if canImport(AppKit)
        if Thread.isMainThread {
            return promptOnMain(defaultRoot: defaultRoot)
        }
        return DispatchQueue.main.sync {
            promptOnMain(defaultRoot: defaultRoot)
        }
        #else
        return nil
        #endif
    }

    #if canImport(AppKit)
    private static func promptOnMain(defaultRoot: URL) -> String? {
        if #available(macOS 10.15, *) {
            return MainActor.assumeIsolated {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = true
                panel.allowsMultipleSelection = false
                panel.title = "Grant access to Apple Notes"
                panel.message = "Select the group.com.apple.notes folder or NoteStore.sqlite to grant access."
                panel.prompt = "Grant Access"
                panel.directoryURL = defaultRoot.deletingLastPathComponent()

                let app = NSApplication.shared
                app.setActivationPolicy(.regular)
                app.activate(ignoringOtherApps: true)

                if panel.runModal() == .OK, let url = panel.url {
                    return url.path
                }
                return nil
            }
        }
        return nil
    }
    #endif

    private static var isInteractive: Bool {
        #if canImport(Darwin)
        return isatty(STDIN_FILENO) == 1
        #else
        return false
        #endif
    }
}
