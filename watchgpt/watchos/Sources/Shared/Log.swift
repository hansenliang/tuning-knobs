import os

enum Log {
    static let api = Logger(subsystem: "app.watchgpt", category: "api")
    static let turn = Logger(subsystem: "app.watchgpt", category: "turn")
    static let live = Logger(subsystem: "app.watchgpt", category: "live")
    static let audio = Logger(subsystem: "app.watchgpt", category: "audio")
    static let store = Logger(subsystem: "app.watchgpt", category: "store")
}
