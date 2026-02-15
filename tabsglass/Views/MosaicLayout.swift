//
//  MosaicLayout.swift
//  tabsglass
//
//  Telegram-style mosaic layout for media groups
//

import UIKit

// MARK: - Media Item (unified photo/video representation)

struct MediaItem {
    let fileName: String
    let isVideo: Bool
    let thumbnailFileName: String?  // For videos, the pre-generated thumbnail
    let duration: Double?           // For videos, duration in seconds

    /// Create a photo media item
    static func photo(_ fileName: String) -> MediaItem {
        MediaItem(fileName: fileName, isVideo: false, thumbnailFileName: nil, duration: nil)
    }

    /// Create a video media item
    static func video(_ fileName: String, thumbnailFileName: String, duration: Double) -> MediaItem {
        MediaItem(fileName: fileName, isVideo: true, thumbnailFileName: thumbnailFileName, duration: duration)
    }
}

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
    private var playOverlays: [UIView] = []      // Play button overlays for videos
    private var durationLabels: [UILabel] = []   // Duration badges for videos
    private var layoutItems: [MosaicLayoutItem] = []
    private var currentFileNames: [String] = []
    private var currentMediaItems: [MediaItem] = []
    /// Corner radius for outer corners (should match bubble corner radius)
    var cornerRadius: CGFloat = 18

    /// Callback when media is tapped: (index, sourceFrame in window coordinates, image, allFileNames, isVideo)
    var onMediaTapped: ((Int, CGRect, UIImage, [String], Bool) -> Void)?

    /// Legacy callback for photos only (backward compatibility)
    var onPhotoTapped: ((Int, CGRect, UIImage, [String]) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Get image view at index for transition animations
    func getImageView(at index: Int) -> UIImageView? {
        guard index >= 0 && index < imageViews.count else { return nil }
        return imageViews[index]
    }

    /// Configure with MediaItems (supports both photos and videos)
    /// - Parameters:
    ///   - mediaItems: Array of MediaItem (photos and videos)
    ///   - aspectRatios: Pre-calculated aspect ratios for layout
    ///   - maxWidth: Maximum width for the mosaic
    ///   - isAtBottom: If true, bottom corners will be rounded
    func configure(with mediaItems: [MediaItem], aspectRatios: [CGFloat], maxWidth: CGFloat, isAtBottom: Bool = true) {
        // Clear old views
        clearViews()
        currentMediaItems = mediaItems
        currentFileNames = mediaItems.map { $0.fileName }

        guard !mediaItems.isEmpty, !aspectRatios.isEmpty else { return }

        // Calculate layout
        let calculator = MosaicLayoutCalculator(maxWidth: maxWidth, maxHeight: 300, spacing: 2)
        layoutItems = calculator.calculateLayout(aspectRatios: aspectRatios)

        // Create image views with placeholder
        for (index, item) in layoutItems.enumerated() {
            guard index < mediaItems.count else { continue }
            let mediaItem = mediaItems[index]

            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = UIColor.systemGray5
            imageView.frame = item.frame

            // Apply corner mask based on position
            var position = item.position
            if !isAtBottom {
                position.remove(.bottom)
            }
            imageView.layer.maskedCorners = cornerMask(for: position)
            imageView.layer.cornerRadius = cornerRadius

            // Enable tap gesture
            imageView.isUserInteractionEnabled = true
            imageView.tag = index
            let tap = UITapGestureRecognizer(target: self, action: #selector(mediaTapped(_:)))
            imageView.addGestureRecognizer(tap)

            addSubview(imageView)
            imageViews.append(imageView)

            // Load thumbnail
            let targetSize = item.frame.size
            let loadStart = CACurrentMediaTime()
            if mediaItem.isVideo, let thumbnailFileName = mediaItem.thumbnailFileName {
                // Load video thumbnail
                ImageCache.shared.loadVideoThumbnail(
                    videoFileName: mediaItem.fileName,
                    thumbnailFileName: thumbnailFileName,
                    targetSize: targetSize
                ) { [weak imageView] image in
                    let loadElapsed = (CACurrentMediaTime() - loadStart) * 1000
                    print("  🎬 VIDEO THUMB \(mediaItem.fileName.prefix(8)) \(String(format: "%.1f", loadElapsed))ms cached=\(loadElapsed < 1)")
                    imageView?.image = image
                }

                // Add play overlay
                let playOverlay = createPlayOverlay(frame: item.frame)
                addSubview(playOverlay)
                playOverlays.append(playOverlay)

                // Add duration badge
                if let duration = mediaItem.duration {
                    let durationLabel = createDurationBadge(duration: duration, frame: item.frame)
                    addSubview(durationLabel)
                    durationLabels.append(durationLabel)
                }
            } else {
                // Load photo thumbnail
                ImageCache.shared.loadThumbnail(for: mediaItem.fileName, targetSize: targetSize) { [weak imageView] image in
                    let loadElapsed = (CACurrentMediaTime() - loadStart) * 1000
                    print("  📷 PHOTO THUMB \(mediaItem.fileName.prefix(8)) \(String(format: "%.1f", loadElapsed))ms cached=\(loadElapsed < 1)")
                    imageView?.image = image
                }
            }
        }

        // Update frame height
        if let maxY = layoutItems.map({ $0.frame.maxY }).max() {
            frame.size.height = maxY
        }
    }

    /// Configure with file names (async loading with cache) - photos only
    /// - Parameters:
    ///   - fileNames: Array of photo file names
    ///   - aspectRatios: Pre-calculated aspect ratios for layout
    ///   - maxWidth: Maximum width for the mosaic
    ///   - isAtBottom: If true, bottom corners will be rounded (for photos-only messages)
    func configure(with fileNames: [String], aspectRatios: [CGFloat], maxWidth: CGFloat, isAtBottom: Bool = true) {
        // Convert to MediaItems and delegate
        let mediaItems = fileNames.map { MediaItem.photo($0) }
        configure(with: mediaItems, aspectRatios: aspectRatios, maxWidth: maxWidth, isAtBottom: isAtBottom)
    }

    /// Configure with images (legacy, still used for initial layout calculation)
    func configure(with images: [UIImage], maxWidth: CGFloat, isAtBottom: Bool = true) {
        // Clear old views
        clearViews()
        currentFileNames = []
        currentMediaItems = []

        guard !images.isEmpty else { return }

        let aspectRatios = images.map { $0.size.width / $0.size.height }
        let calculator = MosaicLayoutCalculator(maxWidth: maxWidth, maxHeight: 300, spacing: 2)
        layoutItems = calculator.calculateLayout(aspectRatios: aspectRatios)

        for (index, item) in layoutItems.enumerated() {
            let imageView = UIImageView(image: images[index])
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.frame = item.frame

            var position = item.position
            if !isAtBottom {
                position.remove(.bottom)
            }
            imageView.layer.maskedCorners = cornerMask(for: position)
            imageView.layer.cornerRadius = cornerRadius

            imageView.isUserInteractionEnabled = true
            imageView.tag = index
            let tap = UITapGestureRecognizer(target: self, action: #selector(mediaTapped(_:)))
            imageView.addGestureRecognizer(tap)

            addSubview(imageView)
            imageViews.append(imageView)
        }

        if let maxY = layoutItems.map({ $0.frame.maxY }).max() {
            frame.size.height = maxY
        }
    }

    private func clearViews() {
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        playOverlays.forEach { $0.removeFromSuperview() }
        playOverlays.removeAll()
        durationLabels.forEach { $0.removeFromSuperview() }
        durationLabels.removeAll()
    }

    // MARK: - Play Overlay

    private func createPlayOverlay(frame: CGRect) -> UIView {
        let overlaySize: CGFloat = 44
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlay.layer.cornerRadius = overlaySize / 2
        overlay.isUserInteractionEnabled = false

        let playIcon = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        playIcon.image = UIImage(systemName: "play.fill", withConfiguration: config)
        playIcon.tintColor = .white
        playIcon.translatesAutoresizingMaskIntoConstraints = false

        overlay.addSubview(playIcon)
        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: overlay.centerXAnchor, constant: 2), // Slight offset for visual balance
            playIcon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])

        overlay.frame = CGRect(
            x: frame.midX - overlaySize / 2,
            y: frame.midY - overlaySize / 2,
            width: overlaySize,
            height: overlaySize
        )

        return overlay
    }

    // MARK: - Duration Badge

    private func createDurationBadge(duration: Double, frame: CGRect) -> UILabel {
        let label = UILabel()
        label.text = formatDuration(duration)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.isUserInteractionEnabled = false

        // Size to fit content with padding
        label.sizeToFit()
        let padding: CGFloat = 8
        let badgeWidth = label.frame.width + padding
        let badgeHeight: CGFloat = 18

        label.frame = CGRect(
            x: frame.maxX - badgeWidth - 6,
            y: frame.maxY - badgeHeight - 6,
            width: badgeWidth,
            height: badgeHeight
        )

        return label
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    /// Calculate total height for given aspect ratios and width
    static func calculateHeight(for aspectRatios: [CGFloat], maxWidth: CGFloat) -> CGFloat {
        guard !aspectRatios.isEmpty else { return 0 }

        let calculator = MosaicLayoutCalculator(maxWidth: maxWidth, maxHeight: 300, spacing: 2)
        let items = calculator.calculateLayout(aspectRatios: aspectRatios)

        return items.map { $0.frame.maxY }.max() ?? 0
    }

    /// Calculate total height for given images and width (legacy)
    static func calculateHeight(for images: [UIImage], maxWidth: CGFloat) -> CGFloat {
        guard !images.isEmpty else { return 0 }

        let aspectRatios = images.map { $0.size.width / $0.size.height }
        return calculateHeight(for: aspectRatios, maxWidth: maxWidth)
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

    @objc private func mediaTapped(_ gesture: UITapGestureRecognizer) {
        guard let imageView = gesture.view as? UIImageView,
              let image = imageView.image,
              let window = window else { return }

        let index = imageView.tag
        let frameInWindow = imageView.convert(imageView.bounds, to: window)

        // Check if this is a video
        let isVideo = index < currentMediaItems.count && currentMediaItems[index].isVideo

        // Call new callback if set
        onMediaTapped?(index, frameInWindow, image, currentFileNames, isVideo)

        // Backward compatibility: call old callback for photos
        if !isVideo {
            onPhotoTapped?(index, frameInWindow, image, currentFileNames)
        }
    }
}
