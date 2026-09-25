import WatchKit

/// Every haptic the app plays, in one place. A2 asks for a tick on start and on send.
@MainActor
enum Haptics {
    static func listenStart() { play(.start) }
    static func send() { play(.click) }
    static func stop() { play(.stop) }
    static func liveReady() { play(.directionUp) }
    static func toggle() { play(.click) }
    static func success() { play(.success) }
    static func failure() { play(.failure) }

    private static func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
