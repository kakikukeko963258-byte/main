import SwiftUI

struct IconMenuSelection {
    let item: HomeItem
    let source: CGRect
    var folderID: String? = nil
}

struct HomeIconMenu: View {
    let selection: IconMenuSelection
    let size: CGSize
    let open: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let width = min(260, size.width * 0.68)
        let height: CGFloat = 150
        let x = min(size.width - width / 2 - 12, max(width / 2 + 12, selection.source.midX))
        let below = selection.source.maxY + 14 + height / 2
        let y = below + height / 2 < size.height - 60
            ? below : max(90 + height / 2, selection.source.minY - 14 - height / 2)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.14).contentShape(Rectangle()).onTapGesture(perform: dismiss)
            Group {
                if selection.item.isFolder { FolderIcon(item: selection.item) }
                else { SlotIcon(slot: selection.item.slots[0]) }
            }
            .frame(width: selection.source.width, height: selection.source.height)
            .scaleEffect(1.06).shadow(color: .black.opacity(0.25), radius: 8, y: 5)
            .position(x: selection.source.midX, y: selection.source.midY)
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                row("開く", symbol: "arrow.up.forward.app", action: open)
                Divider().overlay(.white.opacity(0.1))
                row("ホーム画面を編集", symbol: "square.grid.2x2", action: edit)
                Divider().overlay(.white.opacity(0.1))
                row(selection.folderID == nil ? "ホーム画面から取り除く" : "フォルダから取り出す",
                    symbol: "minus.circle", destructive: true, action: remove)
            }.frame(width: width, height: height).homeGlass(24)
                .position(x: x, y: y)
        }.frame(width: size.width, height: size.height)
            .accessibilityElement(children: .contain).accessibilityLabel("アイコンのメニュー")
    }
    private func row(_ title: String, symbol: String, destructive: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 15))
                Spacer()
                Image(systemName: symbol).font(.system(size: 17))
            }.foregroundStyle(destructive ? Color.red : Color.white)
                .padding(.horizontal, 16).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
