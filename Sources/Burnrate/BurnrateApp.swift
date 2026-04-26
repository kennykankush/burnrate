import BurnrateCore
import SwiftUI

@main
struct BurnrateApp: App {
    @State private var model = MenuBarModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(model: self.model)
                .onAppear {
                    self.model.start()
                }
        } label: {
            MenuBarLabel(model: self.model)
                .task {
                    self.model.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
