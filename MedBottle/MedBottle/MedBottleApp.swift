import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationManager.shared.configure()
        return true
    }
}

@main
struct MedBottleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MedicationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.configure(store: store)
                    NotificationManager.shared.scheduleAllReminders(for: store.medications)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.reloadFromStorage()
                        NotificationManager.shared.configure(store: store)
                        NotificationManager.shared.scheduleAllReminders(for: store.medications)
                    }
                }
        }
    }
}
