import SwiftUI

/// Arranges subviews equidistantly around a circle.
struct RadialLayout: Layout {
    var radius: CGFloat = 80

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxSize = subviews.map { $0.sizeThatFits(.unspecified) }
            .reduce(CGSize.zero) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        let side = (radius + max(maxSize.width, maxSize.height)) * 2
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }
        let angleStep = 2 * Double.pi / Double(count)
        // Start from top (-π/2)
        let startAngle = -Double.pi / 2

        for (index, subview) in subviews.enumerated() {
            let angle = startAngle + angleStep * Double(index)
            let x = bounds.midX + radius * cos(angle)
            let y = bounds.midY + radius * sin(angle)
            subview.place(at: CGPoint(x: x, y: y), anchor: .center, proposal: .unspecified)
        }
    }
}
