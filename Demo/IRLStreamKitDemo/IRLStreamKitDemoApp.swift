import IRLStreamKit
import SwiftUI

@main
struct IRLStreamKitDemoApp: App {
    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
