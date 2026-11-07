import SwiftUI

/// Preview tab: renders the latest UI-description JSON as real SwiftUI.
///
/// This is a *safe* live preview, not runtime Swift compilation:
/// the AI's JSON is decoded into `AICodeUINode` values and rendered only
/// with the components in `UIDescription.swift`. Buttons can only do
/// the named actions (counter +1 / reset, toggle flip). Arbitrary
/// Swift from the AI is never compiled or executed.
///
/// The preview updates live while a chat reply streams in, whenever
/// a complete JSON block can be parsed. Sample prompts work offline.
struct AICodePreviewView: View {
    var onHome: () -> Void = {}
    @Environment(AICodeChatStore.self) private var store
    @State private var previewState = AICodePreviewState()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    if let node = store.currentPreviewNode {
                        VStack(alignment: .leading, spacing: 0) {
                            AICodeUINodeView(node: node, state: previewState)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button("プレビューの状態をリセット") {
                            previewState = AICodePreviewState()
                        }
                        .font(.callout)
                    } else {
                        Text("まだプレビューがありません。チャットで画面を作ってもらうか、サンプルをタップしてください。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(AICodeSamples.all) { sample in
                            Button(sample.title) {
                                store.applySample(sample)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let error = store.previewError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onHome) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("ホームへ戻る")
                }
            }
            .navigationTitle("プレビュー")
        }
    }
}

#Preview {
    AICodePreviewView()
        .environment(AICodeChatStore())
}
