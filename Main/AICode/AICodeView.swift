import SwiftUI

struct AICodeView: View {
    let onHome: () -> Void
    @State private var store = AICodeChatStore.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AICodeChatView(onHome: onHome)
                .tabItem { Label("チャット", systemImage: "message") }
                .tag(0)
            AICodeCodeView(onHome: onHome)
                .tabItem { Label("コード", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(1)
            AICodePreviewView(onHome: onHome)
                .tabItem { Label("プレビュー", systemImage: "eye") }
                .tag(2)
        }
        .environment(store)
    }
}
