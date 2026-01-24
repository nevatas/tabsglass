//
//  MosaicLayout.swift
//  tabsglass
//
//  Telegram-style mosaic layout for media groups
//

import UIKit

// MARK: - Position Flags

struct MosaicItemPosition: OptionSet {
    let rawValue: Int

    static let none = MosaicItemPosition([])
    static let top = MosaicItemPosition(rawValue: 1 << 0)
    static let bottom = MosaicItemPosition(rawValue: 1 << 1)
    static let left = MosaicItemPosition(rawValue: 1 << 2)
    static let right = MosaicItemPosition(rawValue: 1 << 3)

    // Corners for rounded corners
    static let topLeft: MosaicItemPosition = [.top, .left]
    static let topRight: MosaicItemPosition = [.top, .right]
    static let bottomLeft: MosaicItemPosition = [.bottom, .left]
    static let bottomRight: MosaicItemPosition = [.bottom, .right]

    // Check corner positions
    var isTopLeft: Bool { contains(.top) && contains(.left) }
    var isTopRight: Bool { contains(.top) && contains(.right) }
    var isBottomLeft: Bool { contains(.bottom) && contains(.left) }
    var isBottomRight: Bool { contains(.bottom) && contains(.right) }
}

// MARK: - Layout Item

struct MosaicLayoutItem {
    let frame: CGRect
    let position: MosaicItemPosition
    let index: Int
}

// MARK: - Aspect Ratio Classification

private enum AspectRatioType {
    case wide       // w/h > 1.2 (horizontal)
    case narrow     // w/h < 0.8 (vertical)
    case square     // 0.8 <= w/h <= 1.2

    init(ratio: CGFloat) {
        if ratio > 1.2 {
            self = .wide
        } else if ratio < 0.8 {
            self = .narrow
        } else {
            self = .square
        }
    }
}

// MARK: - Layout Calculator

struct MosaicLayoutCalculator {
    /// Container width for layout
    let maxWidth: CGFloat

    /// Maximum height for the entire mosaic
    let maxHeight: CGFloat

    /// Spacing between items
    let spacing: CGFloat

    init(maxWidth: CGFloat, maxHeight: CGFloat = 400, spacing: CGFloat = 2) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.spacing = spacing
    }

    /// Calculate layout for given aspect ratios
    /// - Parameter aspectRatios: Array of width/height ratios for each item
    /// - Returns: Array of layout items with frames and positions
    func calculateLayout(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        guard !aspectRatios.isEmpty else { return [] }

        let count = aspectRatios.count

        switch count {
        case 1:
            return layoutSingle(aspectRatio: aspectRatios[0])
        case 2:
            return layoutTwo(aspectRatios: aspectRatios)
        case 3:
            return layoutThree(aspectRatios: aspectRatios)
        case 4:
            return layoutFour(aspectRatios: aspectRatios)
        default:
            return layoutFiveOrMore(aspectRatios: aspectRatios)
        }
    }

    // MARK: - Single Item

    private func layoutSingle(aspectRatio: CGFloat) -> [MosaicLayoutItem] {
        // Single item fills the width, height based on aspect ratio
        let width = maxWidth
        let height = min(width / aspectRatio, maxHeight)

        return [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: width, height: height),
                position: [.top, .bottom, .left, .right],
                index: 0
            )
        ]
    }

    // MARK: - Two Items

    private func layoutTwo(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let type0 = AspectRatioType(ratio: aspectRatios[0])
        let type1 = AspectRatioType(ratio: aspectRatios[1])

        // Both wide → stack vertically
        if type0 == .wide && type1 == .wide {
            return layoutTwoVertical(aspectRatios: aspectRatios)
        }

        // Both narrow → side by side
        if type0 == .narrow && type1 == .narrow {
            return layoutTwoHorizontal(aspectRatios: aspectRatios)
        }

        // Default: side by side with proportional widths
        return layoutTwoHorizontal(aspectRatios: aspectRatios)
    }

    private func layoutTwoVertical(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let width = maxWidth
        let totalHeight = min(maxHeight, width / 2)
        let height = (totalHeight - spacing) / 2

        return [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: width, height: height),
                position: [.top, .left, .right],
                index: 0
            ),
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: height + spacing, width: width, height: height),
                position: [.bottom, .left, .right],
                index: 1
            )
        ]
    }

    private func layoutTwoHorizontal(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        // Calculate proportional widths based on aspect ratios
        let ratio0 = aspectRatios[0]
        let ratio1 = aspectRatios[1]

        let totalRatio = ratio0 + ratio1
        let width0 = ((maxWidth - spacing) * ratio0 / totalRatio).rounded()
        let width1 = maxWidth - spacing - width0

        // Height based on average
        let avgRatio = (ratio0 + ratio1) / 2
        let height = min(maxWidth / avgRatio, maxHeight)

        return [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: width0, height: height),
                position: [.top, .bottom, .left],
                index: 0
            ),
            MosaicLayoutItem(
                frame: CGRect(x: width0 + spacing, y: 0, width: width1, height: height),
                position: [.top, .bottom, .right],
                index: 1
            )
        ]
    }

    // MARK: - Three Items

    private func layoutThree(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let type0 = AspectRatioType(ratio: aspectRatios[0])

        // First is wide → one on top, two below
        if type0 == .wide {
            return layoutThreeTopOne(aspectRatios: aspectRatios)
        }

        // First is narrow/square → one on left, two on right stacked
        return layoutThreeLeftOne(aspectRatios: aspectRatios)
    }

    private func layoutThreeTopOne(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let totalHeight = min(maxHeight, maxWidth * 0.75)
        let topHeight = totalHeight * 0.6
        let bottomHeight = totalHeight - topHeight - spacing

        let bottomWidth = (maxWidth - spacing) / 2

        return [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: maxWidth, height: topHeight),
                position: [.top, .left, .right],
                index: 0
            ),
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: topHeight + spacing, width: bottomWidth, height: bottomHeight),
                position: [.bottom, .left],
                index: 1
            ),
            MosaicLayoutItem(
                frame: CGRect(x: bottomWidth + spacing, y: topHeight + spacing, width: bottomWidth, height: bottomHeight),
                position: [.bottom, .right],
                index: 2
            )
        ]
    }

    private func layoutThreeLeftOne(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let totalHeight = min(maxHeight, maxWidth * 0.75)
        let leftWidth = maxWidth * 0.6
        let rightWidth = maxWidth - leftWidth - spacing
        let rightHeight = (totalHeight - spacing) / 2

        return [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: leftWidth, height: totalHeight),
                position: [.top, .bottom, .left],
                index: 0
            ),
            MosaicLayoutItem(
                frame: CGRect(x: leftWidth + spacing, y: 0, width: rightWidth, height: rightHeight),
                position: [.top, .right],
                index: 1
            ),
            MosaicLayoutItem(
                frame: CGRect(x: leftWidth + spacing, y: rightHeight + spacing, width: rightWidth, height: rightHeight),
                position: [.bottom, .right],
                index: 2
            )
        ]
    }

    // MARK: - Four Items

    private func layoutFour(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let type0 = AspectRatioType(ratio: aspectRatios[0])

        // First is wide → one on top, three below
        if type0 == .wide {
            return layoutFourTopOne(aspectRatios: aspectRatios)
        }

        // Otherwise → 2x2 grid
        return layoutFourGrid(aspectRatios: aspectRatios)
    }

    private func layoutFourTopOne(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let totalHeight = min(maxHeight, maxWidth * 0.75)
        let topHeight = totalHeight * 0.55
        let bottomHeight = totalHeight - topHeight - spacing

        let bottomWidth = (maxWidth - 2 * spacing) / 3

        return [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: maxWidth, height: topHeight),
                position: [.top, .left, .right],
                index: 0
            ),
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: topHeight + spacing, width: bottomWidth, height: bottomHeight),
                position: [.bottom, .left],
                index: 1
            ),
            MosaicLayoutItem(
                frame: CGRect(x: bottomWidth + spacing, y: topHeight + spacing, width: bottomWidth, height: bottomHeight),
                position: [.bottom],
                index: 2
            ),
            MosaicLayoutItem(
                frame: CGRect(x: 2 * (bottomWidth + spacing), y: topHeight + spacing, width: bottomWidth, height: bottomHeight),
                position: [.bottom, .right],
                index: 3
            )
        ]
    }

    private func layoutFourGrid(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let cellWidth = (maxWidth - spacing) / 2
        let cellHeight = cellWidth // Square cells
        let totalHeight = min(maxHeight, 2 * cellHeight + spacing)
        let adjustedHeight = (totalHeight - spacing) / 2

        return [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: cellWidth, height: adjustedHeight),
                position: [.top, .left],
                index: 0
            ),
            MosaicLayoutItem(
                frame: CGRect(x: cellWidth + spacing, y: 0, width: cellWidth, height: adjustedHeight),
                position: [.top, .right],
                index: 1
            ),
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: adjustedHeight + spacing, width: cellWidth, height: adjustedHeight),
                position: [.bottom, .left],
                index: 2
            ),
            MosaicLayoutItem(
                frame: CGRect(x: cellWidth + spacing, y: adjustedHeight + spacing, width: cellWidth, height: adjustedHeight),
                position: [.bottom, .right],
                index: 3
            )
        ]
    }

    // MARK: - Five or More Items

    private func layoutFiveOrMore(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let type0 = AspectRatioType(ratio: aspectRatios[0])

        // First is wide → one on top, rest below in grid
        if type0 == .wide {
            return layoutFiveOrMoreTopOne(aspectRatios: aspectRatios)
        }

        // First is narrow → one on left, rest on right in grid
        if type0 == .narrow {
            return layoutFiveOrMoreLeftOne(aspectRatios: aspectRatios)
        }

        // Mixed → 2 on top, rest below
        return layoutFiveOrMoreTwoTop(aspectRatios: aspectRatios)
    }

    private func layoutFiveOrMoreTopOne(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let count = aspectRatios.count
        let bottomCount = count - 1

        let totalHeight = min(maxHeight, maxWidth * 0.8)
        let topHeight = totalHeight * 0.5
        let bottomHeight = totalHeight - topHeight - spacing

        let bottomWidth = (maxWidth - CGFloat(bottomCount - 1) * spacing) / CGFloat(bottomCount)

        var items: [MosaicLayoutItem] = [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: maxWidth, height: topHeight),
                position: [.top, .left, .right],
                index: 0
            )
        ]

        for i in 1..<count {
            let x = CGFloat(i - 1) * (bottomWidth + spacing)
            var position: MosaicItemPosition = [.bottom]
            if i == 1 { position.insert(.left) }
            if i == count - 1 { position.insert(.right) }

            items.append(MosaicLayoutItem(
                frame: CGRect(x: x, y: topHeight + spacing, width: bottomWidth, height: bottomHeight),
                position: position,
                index: i
            ))
        }

        return items
    }

    private func layoutFiveOrMoreLeftOne(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let count = aspectRatios.count
        let rightCount = count - 1

        let totalHeight = min(maxHeight, maxWidth * 0.8)
        let leftWidth = maxWidth * 0.55
        let rightWidth = maxWidth - leftWidth - spacing

        let rows = (rightCount + 1) / 2
        let rightItemHeight = (totalHeight - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        let rightItemWidth = (rightWidth - spacing) / 2

        var items: [MosaicLayoutItem] = [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: leftWidth, height: totalHeight),
                position: [.top, .bottom, .left],
                index: 0
            )
        ]

        for i in 1..<count {
            let idx = i - 1
            let row = idx / 2
            let col = idx % 2

            let x = leftWidth + spacing + CGFloat(col) * (rightItemWidth + spacing)
            let y = CGFloat(row) * (rightItemHeight + spacing)

            var position: MosaicItemPosition = []
            if row == 0 { position.insert(.top) }
            if row == rows - 1 { position.insert(.bottom) }
            if col == 1 { position.insert(.right) }

            items.append(MosaicLayoutItem(
                frame: CGRect(x: x, y: y, width: rightItemWidth, height: rightItemHeight),
                position: position,
                index: i
            ))
        }

        return items
    }

    private func layoutFiveOrMoreTwoTop(aspectRatios: [CGFloat]) -> [MosaicLayoutItem] {
        let count = aspectRatios.count
        let bottomCount = count - 2

        let totalHeight = min(maxHeight, maxWidth * 0.8)
        let topHeight = totalHeight * 0.5
        let bottomHeight = totalHeight - topHeight - spacing

        let topWidth = (maxWidth - spacing) / 2
        let bottomWidth = (maxWidth - CGFloat(bottomCount - 1) * spacing) / CGFloat(bottomCount)

        var items: [MosaicLayoutItem] = [
            MosaicLayoutItem(
                frame: CGRect(x: 0, y: 0, width: topWidth, height: topHeight),
                position: [.top, .left],
                index: 0
            ),
            MosaicLayoutItem(
                frame: CGRect(x: topWidth + spacing, y: 0, width: topWidth, height: topHeight),
                position: [.top, .right],
                index: 1
            )
        ]

        for i in 2..<count {
            let x = CGFloat(i - 2) * (bottomWidth + spacing)
            var position: MosaicItemPosition = [.bottom]
            if i == 2 { position.insert(.left) }
            if i == count - 1 { position.insert(.right) }

            items.append(MosaicLayoutItem(
                frame: CGRect(x: x, y: topHeight + spacing, width: bottomWidth, height: bottomHeight),
                position: position,
                index: i
            ))
        }

        return items
    }
}

// MARK: - Mosaic View

final class MosaicMediaView: UIView {
    private var imageViews: [UIImageView] = []
    private var layoutItems: [MosaicLayoutItem] = []
    /// Corner radius for outer corners (should match bubble corner radius)
    var cornerRadius: CGFloat = 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configure with images
    /// - Parameters:
    ///   - images: Array of images to display
    ///   - maxWidth: Maximum width for the mosaic
    ///   - isAtBottom: If true, bottom corners will be rounded (for photos-only messages)
    func configure(with images: [UIImage], maxWidth: CGFloat, isAtBottom: Bool = true) {
        // Clear old views
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()

        guard !images.isEmpty else { return }

        // Calculate aspect ratios
        let aspectRatios = images.map { $0.size.width / $0.size.height }

        // Calculate layout
        let calculator = MosaicLayoutCalculator(maxWidth: maxWidth, maxHeight: 300, spacing: 2)
        layoutItems = calculator.calculateLayout(aspectRatios: aspectRatios)

        // Create image views
        for (index, item) in layoutItems.enumerated() {
            let imageView = UIImageView(image: images[index])
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.frame = item.frame

            // Apply corner mask based on position
            // If not at bottom of bubble, remove bottom corners from the mask
            var position = item.position
            if !isAtBottom {
                position.remove(.bottom)
            }
            imageView.layer.maskedCorners = cornerMask(for: position)
            imageView.layer.cornerRadius = cornerRadius

            addSubview(imageView)
            imageViews.append(imageView)
        }

        // Update frame height
        if let maxY = layoutItems.map({ $0.frame.maxY }).max() {
            frame.size.height = maxY
        }
    }

    /// Calculate total height for given images and width
    static func calculateHeight(for images: [UIImage], maxWidth: CGFloat) -> CGFloat {
        guard !images.isEmpty else { return 0 }

        let aspectRatios = images.map { $0.size.width / $0.size.height }
        let calculator = MosaicLayoutCalculator(maxWidth: maxWidth, maxHeight: 300, spacing: 2)
        let items = calculator.calculateLayout(aspectRatios: aspectRatios)

        return items.map { $0.frame.maxY }.max() ?? 0
    }

    private func cornerMask(for position: MosaicItemPosition) -> CACornerMask {
        var mask: CACornerMask = []

        if position.isTopLeft {
            mask.insert(.layerMinXMinYCorner)
        }
        if position.isTopRight {
            mask.insert(.layerMaxXMinYCorner)
        }
        if position.isBottomLeft {
            mask.insert(.layerMinXMaxYCorner)
        }
        if position.isBottomRight {
            mask.insert(.layerMaxXMaxYCorner)
        }

        return mask
    }

    override var intrinsicContentSize: CGSize {
        let height = layoutItems.map { $0.frame.maxY }.max() ?? 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
}
