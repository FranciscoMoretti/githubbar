import SwiftUI

struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var shortcut: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 11.5))
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .frame(height: 27)
        }
        .buttonStyle(.plain)
    }
}
