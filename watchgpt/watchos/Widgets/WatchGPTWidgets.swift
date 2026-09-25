import SwiftUI
import WidgetKit

@main
struct WatchGPTWidgetBundle: WidgetBundle {
    var body: some Widget {
        AskComplication()      // D1 (mic): opens into Listening
        LiveComplication()     // D1 (waveform): opens into Live
        SmartStackWidget()     // D2
        TalkControl()          // D3: Control Center, Smart Stack, Ultra Action button
    }
}
