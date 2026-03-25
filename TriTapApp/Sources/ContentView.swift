import SwiftUI
import TypingAuthSDK

struct ContentView: View {
    @State private var isEnrolled = TypingAuthSDK.shared.isEnrolled

    var body: some View {
        NavigationStack {
            PersonalModeView(isEnrolled: $isEnrolled)
                .navigationTitle("TriTap")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
