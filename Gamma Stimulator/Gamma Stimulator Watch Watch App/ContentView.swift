import SwiftUI

struct ContentView: View {
    @State private var status = "Ready"
    
    var body: some View {
        VStack {
            Text(status)
                .font(.system(.headline))
                .padding()
            
            Text("40 Hz Haptic")
                .font(.system(.subheadline))
        }
        .onAppear {
            // Setup notification observer
            setupStatusObserver()
            // Initialize WatchSessionManager
            _ = WatchSessionManager.shared
        }
    }
    
    private func setupStatusObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StatusUpdate"),
            object: nil,
            queue: .main
        ) { notification in
            if let status = notification.userInfo?["status"] as? String {
                self.status = status
            }
        }
    }
}
