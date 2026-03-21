import SwiftUI
import UIKit

/// Identifiable wrapper for items to share via the iOS share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// UIActivityViewController wrapper for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
