//
//  GalleryViewController.swift
//  tabsglass
//
//  Telegram-style fullscreen gallery viewer for photos and videos
//

import UIKit
import AVKit

// MARK: - Gallery Media Item

/// Represents a media item in the gallery (photo or video)
enum GalleryMediaItem {
    case photo(image: UIImage)
    case video(url: URL, thumbnail: UIImage?)

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }

    var thumbnail: UIImage? {
        switch self {
        case .photo(let image):
            return image
        case .video(_, let thumbnail):
            return thumbnail
        }
    }
}

// MARK: - Gallery View Controller

final class GalleryViewController: UIViewController {

    // MARK: - Properties

    private let mediaItems: [GalleryMediaItem]
    private var currentIndex: Int
    private let sourceFrame: CGRect?
    private let sourceImage: UIImage?

    // Views
    private let backgroundView = UIView()
    private let dismissScrollView = UIScrollView()
    private let contentView = UIView()
    private var pageViewController: UIPageViewController!
    private let closeButton = UIButton(type: .system)
    private let pageControl = UIPageControl()

    // State
    private var isZoomed = false
    private var centerOffset: CGFloat = 0
    private var hasLaidOutInitially = false

    // Callbacks
    var onDismiss: (() -> Void)?

    // MARK: - Init

    /// Initialize with media items (photos and/or videos)
    init(mediaItems: [GalleryMediaItem], startIndex: Int, sourceFrame: CGRect?, sourceImage: UIImage?) {
        self.mediaItems = mediaItems
        self.currentIndex = startIndex
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    /// Convenience initializer for photo-only galleries (backwards compatibility)
    convenience init(photos: [UIImage], startIndex: Int, sourceFrame: CGRect?, sourceImage: UIImage?) {
        let items = photos.map { GalleryMediaItem.photo(image: $0) }
        self.init(mediaItems: items, startIndex: startIndex, sourceFrame: sourceFrame, sourceImage: sourceImage)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupDismissScrollView()
        setupPageViewController()
        setupCloseButton()
        setupPageControl()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutForBounds()
    }

    private func updateLayoutForBounds() {
        let viewHeight = view.bounds.height
        let viewWidth = view.bounds.width

        // Update content view and scroll view content size
        contentView.frame = CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight * 3)
        dismissScrollView.contentSize = contentView.bounds.size

        // Update page view controller frame
        pageViewController.view.frame = CGRect(x: 0, y: viewHeight, width: viewWidth, height: viewHeight)

        // Update center offset and scroll position only on initial layout
        centerOffset = viewHeight
        if !hasLaidOutInitially {
            hasLaidOutInitially = true
            dismissScrollView.contentOffset.y = centerOffset
        }
    }

    // MARK: - Setup

    private func setupBackground() {
        backgroundView.backgroundColor = .black
        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundView)
    }

    private func setupDismissScrollView() {
        dismissScrollView.frame = view.bounds
        dismissScrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dismissScrollView.showsVerticalScrollIndicator = false
        dismissScrollView.showsHorizontalScrollIndicator = false
        dismissScrollView.bounces = true
        dismissScrollView.delegate = self
        dismissScrollView.decelerationRate = .fast
        view.addSubview(dismissScrollView)

        // Content view will be sized in viewDidLayoutSubviews
        dismissScrollView.addSubview(contentView)
    }

    private func setupPageViewController() {
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pageViewController.dataSource = self
        pageViewController.delegate = self

        // Frame will be set in viewDidLayoutSubviews
        addChild(pageViewController)
        contentView.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)

        // Set initial page
        let initialVC = makePageController(for: currentIndex)
        pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)
    }

    private func setupCloseButton() {
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        closeButton.layer.cornerRadius = 16
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setupPageControl() {
        guard mediaItems.count > 1 else { return }

        pageControl.numberOfPages = mediaItems.count
        pageControl.currentPage = currentIndex
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.3)
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.isUserInteractionEnabled = false
        view.addSubview(pageControl)

        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismissGallery()
    }

    private func dismissGallery() {
        onDismiss?()
        dismiss(animated: true)
    }

    // MARK: - Page Controller Factory

    private func makePageController(for index: Int) -> UIViewController & GalleryPageProtocol {
        let item = mediaItems[index]

        switch item {
        case .photo(let image):
            let vc = GalleryPageViewController(image: image, index: index)
            vc.onZoomChange = { [weak self] isZoomed in
                self?.handleZoomChange(isZoomed)
            }
            vc.onSingleTap = { [weak self] in
                self?.toggleUI()
            }
            return vc

        case .video(let url, _):
            let vc = GalleryVideoPageViewController(videoURL: url, index: index)
            vc.onSingleTap = { [weak self] in
                self?.toggleUI()
            }
            return vc
        }
    }

    private func handleZoomChange(_ zoomed: Bool) {
        isZoomed = zoomed
        dismissScrollView.isScrollEnabled = !zoomed
    }

    private func toggleUI() {
        let newAlpha: CGFloat = closeButton.alpha > 0.5 ? 0 : 1
        UIView.animate(withDuration: 0.2) {
            self.closeButton.alpha = newAlpha
            self.pageControl.alpha = newAlpha
        }
    }
}

// MARK: - UIScrollViewDelegate (Swipe-to-Dismiss)

extension GalleryViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === dismissScrollView, !isZoomed else { return }

        let delta = scrollView.contentOffset.y - centerOffset
        // Update background alpha based on drag distance
        let progress = min(abs(delta) / 150, 1.0)
        backgroundView.alpha = 1.0 - progress * 0.5
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === dismissScrollView, !isZoomed else { return }
        handleDismissGesture(scrollView, decelerate: decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === dismissScrollView, !isZoomed else { return }
        // Snap back to center if not dismissed
        if abs(scrollView.contentOffset.y - centerOffset) < 150 {
            snapToCenter()
        }
    }

    private func handleDismissGesture(_ scrollView: UIScrollView, decelerate: Bool) {
        let delta = scrollView.contentOffset.y - centerOffset
        let velocity = abs(scrollView.panGestureRecognizer.velocity(in: view).y)
        let threshold: CGFloat = 150
        let velocityThreshold: CGFloat = 1000

        if abs(delta) > threshold || velocity > velocityThreshold {
            // Dismiss
            let direction: CGFloat = delta > 0 ? 1 : -1
            animateDismiss(direction: direction)
        } else if !decelerate {
            // Snap back
            snapToCenter()
        }
    }

    private func snapToCenter() {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.dismissScrollView.contentOffset.y = self.centerOffset
            self.backgroundView.alpha = 1.0
        }
    }

    private func animateDismiss(direction: CGFloat) {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, animations: {
            self.dismissScrollView.contentOffset.y = self.centerOffset + direction * self.view.bounds.height
            self.backgroundView.alpha = 0
            self.closeButton.alpha = 0
            self.pageControl.alpha = 0
        }) { _ in
            self.dismissGallery()
        }
    }
}

// MARK: - UIPageViewControllerDataSource

extension GalleryViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? GalleryPageProtocol else { return nil }
        let index = vc.index - 1
        guard index >= 0 else { return nil }
        return makePageController(for: index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? GalleryPageProtocol else { return nil }
        let index = vc.index + 1
        guard index < mediaItems.count else { return nil }
        return makePageController(for: index)
    }
}

// MARK: - UIPageViewControllerDelegate

extension GalleryViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let currentVC = pageViewController.viewControllers?.first as? GalleryPageProtocol else { return }
        currentIndex = currentVC.index
        pageControl.currentPage = currentIndex

        // Pause video on previous page if it was a video
        for vc in previousViewControllers {
            if let videoVC = vc as? GalleryVideoPageViewController {
                videoVC.pause()
            }
        }
    }
}

// MARK: - UIViewControllerTransitioningDelegate

extension GalleryViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return GalleryOpenTransition(sourceFrame: sourceFrame, sourceImage: sourceImage)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return GalleryCloseTransition(sourceFrame: sourceFrame)
    }
}

// MARK: - Gallery Page Protocol

protocol GalleryPageProtocol: AnyObject {
    var index: Int { get }
    var onSingleTap: (() -> Void)? { get set }
}

// MARK: - Gallery Page View Controller (Photo)

final class GalleryPageViewController: UIViewController, GalleryPageProtocol {

    let index: Int
    private let image: UIImage

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    var onZoomChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?

    init(image: UIImage, index: Int) {
        self.image = image
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupScrollView()
        setupImageView()
        setupGestures()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateZoomScale()
        centerImage()
    }

    private func setupScrollView() {
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        view.addSubview(scrollView)
    }

    private func setupImageView() {
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.frame = view.bounds
        scrollView.addSubview(imageView)
    }

    private func setupGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
    }

    private func updateZoomScale() {
        guard image.size.width > 0, image.size.height > 0 else { return }

        let boundsSize = view.bounds.size
        let imageSize = image.size

        // Calculate min scale (fit image to screen) - Telegram approach
        let widthScale = boundsSize.width / imageSize.width
        let heightScale = boundsSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)

        // Calculate max scale - Telegram uses max(fillScale, minScale * 3.0)
        // We use 5.0 multiplier for more zoom capability
        let fillScale = max(widthScale, heightScale)
        let maxScale = max(fillScale, minScale * 5.0)

        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale

        // Set initial zoom to minimum (fit)
        if scrollView.zoomScale < minScale || scrollView.zoomScale == 1.0 {
            scrollView.zoomScale = minScale
        }

        // Update image view frame at minimum scale
        let scaledWidth = imageSize.width * minScale
        let scaledHeight = imageSize.height * minScale
        imageView.frame = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
        scrollView.contentSize = imageView.frame.size

        // Disable scroll when at minimum zoom (Telegram behavior)
        scrollView.isScrollEnabled = scrollView.zoomScale > minScale + 0.01
    }

    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // Telegram logic: use <= for comparison to handle floating point
        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
            // At minimum → zoom IN to tap location at maximum scale
            let location = gesture.location(in: imageView)
            let zoomRect = zoomRectForScale(scrollView.maximumZoomScale, center: location)
            scrollView.zoom(to: zoomRect, animated: true)
        } else {
            // Zoomed in → zoom OUT to minimum (fit)
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    private func zoomRectForScale(_ scale: CGFloat, center: CGPoint) -> CGRect {
        let width = scrollView.bounds.width / scale
        let height = scrollView.bounds.height / scale
        let x = center.x - width / 2
        let y = center.y - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - UIScrollViewDelegate (Zoom)

extension GalleryPageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()

        // Telegram: disable scroll when at minimum zoom
        let isAtMinimum = scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01
        scrollView.isScrollEnabled = !isAtMinimum

        // Notify parent about zoom state
        onZoomChange?(!isAtMinimum)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Ensure we snap to exactly minimum if very close (prevents floating point issues)
        if scale < scrollView.minimumZoomScale + 0.01 && scale != scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }
    }
}

// MARK: - Gallery Video Page View Controller

final class GalleryVideoPageViewController: UIViewController, GalleryPageProtocol {

    let index: Int
    private let videoURL: URL

    // Player
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    private var isPlaying = false
    private var isSeeking = false

    // Controls
    private let controlsContainer = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let scrubber = UISlider()
    private let currentTimeLabel = UILabel()
    private let remainingTimeLabel = UILabel()
    private let scrubberContainer = UIView()

    // State
    private var controlsVisible = true
    private var autoHideTimer: Timer?
    private var duration: Double = 0

    var onSingleTap: (() -> Void)?

    // MARK: - Init

    init(videoURL: URL, index: Int) {
        self.videoURL = videoURL
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupPlayer()
        setupControls()
        setupGestures()
        setupNotifications()
        setupTimeObserver()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        play()
        scheduleAutoHide()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pause()
        autoHideTimer?.invalidate()
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        autoHideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupPlayer() {
        let player = AVPlayer(url: videoURL)
        self.player = player

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer

        // Load duration
        Task {
            if let item = player.currentItem {
                let duration = try? await item.asset.load(.duration)
                if let duration = duration {
                    await MainActor.run {
                        self.duration = CMTimeGetSeconds(duration)
                        self.updateTimeLabels(currentTime: 0)
                    }
                }
            }
        }
    }

    private func setupControls() {
        // Controls container (for fade animation)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsContainer)

        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainer.topAnchor.constraint(equalTo: view.topAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Center play/pause button
        let config = UIImage.SymbolConfiguration(pointSize: 54, weight: .medium)
        playPauseButton.setImage(UIImage(systemName: "pause.circle.fill", withConfiguration: config), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)

        // Add shadow to button
        playPauseButton.layer.shadowColor = UIColor.black.cgColor
        playPauseButton.layer.shadowOffset = .zero
        playPauseButton.layer.shadowRadius = 8
        playPauseButton.layer.shadowOpacity = 0.5

        controlsContainer.addSubview(playPauseButton)

        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 70),
            playPauseButton.heightAnchor.constraint(equalToConstant: 70)
        ])

        // Scrubber container (above page indicator, no background)
        scrubberContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(scrubberContainer)

        NSLayoutConstraint.activate([
            scrubberContainer.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            scrubberContainer.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            scrubberContainer.bottomAnchor.constraint(equalTo: controlsContainer.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            scrubberContainer.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Time labels with shadow for visibility
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        currentTimeLabel.textColor = .white
        currentTimeLabel.text = "0:00"
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentTimeLabel.layer.shadowColor = UIColor.black.cgColor
        currentTimeLabel.layer.shadowOffset = .zero
        currentTimeLabel.layer.shadowRadius = 4
        currentTimeLabel.layer.shadowOpacity = 0.8

        remainingTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        remainingTimeLabel.textColor = .white
        remainingTimeLabel.text = "-0:00"
        remainingTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        remainingTimeLabel.layer.shadowColor = UIColor.black.cgColor
        remainingTimeLabel.layer.shadowOffset = .zero
        remainingTimeLabel.layer.shadowRadius = 4
        remainingTimeLabel.layer.shadowOpacity = 0.8

        scrubberContainer.addSubview(currentTimeLabel)
        scrubberContainer.addSubview(remainingTimeLabel)

        // Scrubber slider
        scrubber.minimumValue = 0
        scrubber.maximumValue = 1
        scrubber.value = 0
        scrubber.minimumTrackTintColor = .white
        scrubber.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        scrubber.addTarget(self, action: #selector(scrubberValueChanged), for: .valueChanged)
        scrubber.addTarget(self, action: #selector(scrubberTouchDown), for: .touchDown)
        scrubber.addTarget(self, action: #selector(scrubberTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        // Custom thumb (smaller, like Telegram)
        let thumbSize: CGFloat = 12
        let thumbImage = createThumbImage(size: thumbSize, color: .white)
        scrubber.setThumbImage(thumbImage, for: .normal)
        scrubber.setThumbImage(thumbImage, for: .highlighted)

        scrubberContainer.addSubview(scrubber)

        NSLayoutConstraint.activate([
            currentTimeLabel.leadingAnchor.constraint(equalTo: scrubberContainer.leadingAnchor, constant: 16),
            currentTimeLabel.centerYAnchor.constraint(equalTo: scrubberContainer.centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 45),

            remainingTimeLabel.trailingAnchor.constraint(equalTo: scrubberContainer.trailingAnchor, constant: -16),
            remainingTimeLabel.centerYAnchor.constraint(equalTo: scrubberContainer.centerYAnchor),
            remainingTimeLabel.widthAnchor.constraint(equalToConstant: 50),

            scrubber.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8),
            scrubber.trailingAnchor.constraint(equalTo: remainingTimeLabel.leadingAnchor, constant: -8),
            scrubber.centerYAnchor.constraint(equalTo: scrubberContainer.centerYAnchor)
        ])
    }

    private func createThumbImage(size: CGFloat, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }

            let currentTime = CMTimeGetSeconds(time)
            self.updateTimeLabels(currentTime: currentTime)

            if self.duration > 0 {
                self.scrubber.value = Float(currentTime / self.duration)
            }
        }
    }

    // MARK: - Time Formatting

    private func updateTimeLabels(currentTime: Double) {
        currentTimeLabel.text = formatTime(currentTime)

        let remaining = max(0, duration - currentTime)
        remainingTimeLabel.text = "-" + formatTime(remaining)
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }

        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Controls Visibility

    private func toggleControls() {
        setControlsVisible(!controlsVisible)
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool = true) {
        controlsVisible = visible

        if visible {
            scheduleAutoHide()
        } else {
            autoHideTimer?.invalidate()
        }

        let alpha: CGFloat = visible ? 1.0 : 0.0

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.controlsContainer.alpha = alpha
            }
        } else {
            controlsContainer.alpha = alpha
        }
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()

        // Auto-hide after 4 seconds (like Telegram)
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.setControlsVisible(false)
        }
    }

    // MARK: - Actions

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)

        // Ignore taps on scrubber area
        let scrubberFrame = scrubberContainer.convert(scrubberContainer.bounds, to: view)
        if scrubberFrame.contains(location) {
            return
        }

        toggleControls()
        onSingleTap?()
    }

    @objc private func playPauseButtonTapped() {
        if isPlaying {
            pause()
        } else {
            play()
        }
        scheduleAutoHide()
    }

    @objc private func scrubberValueChanged() {
        let targetTime = Double(scrubber.value) * duration
        updateTimeLabels(currentTime: targetTime)
    }

    @objc private func scrubberTouchDown() {
        isSeeking = true
        autoHideTimer?.invalidate()
    }

    @objc private func scrubberTouchUp() {
        let targetTime = Double(scrubber.value) * duration
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isSeeking = false
        }

        scheduleAutoHide()
    }

    @objc private func playerDidFinish() {
        // Reset to beginning
        player?.seek(to: .zero)
        scrubber.value = 0
        updateTimeLabels(currentTime: 0)

        // Show controls and pause
        pause()
        setControlsVisible(true)
    }

    // MARK: - Playback Control

    func play() {
        player?.play()
        isPlaying = true
        updatePlayPauseButton()
        scheduleAutoHide()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updatePlayPauseButton()
        autoHideTimer?.invalidate()
    }

    private func updatePlayPauseButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 54, weight: .medium)
        let imageName = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
    }
}

// MARK: - Open Transition

final class GalleryOpenTransition: NSObject, UIViewControllerAnimatedTransitioning {

    private let sourceFrame: CGRect?
    private let sourceImage: UIImage?

    init(sourceFrame: CGRect?, sourceImage: UIImage?) {
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.25
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let toVC = transitionContext.viewController(forKey: .to) as? GalleryViewController,
              let toView = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toVC)

        if let sourceFrame = sourceFrame, let sourceImage = sourceImage {
            // Animated transition from thumbnail
            let snapshotView = UIImageView(image: sourceImage)
            snapshotView.contentMode = .scaleAspectFill
            snapshotView.clipsToBounds = true
            snapshotView.frame = sourceFrame

            toView.frame = finalFrame
            toView.alpha = 0
            container.addSubview(toView)
            container.addSubview(snapshotView)

            // Calculate final image frame
            let imageAspect = sourceImage.size.width / sourceImage.size.height
            let screenAspect = finalFrame.width / finalFrame.height
            var targetFrame: CGRect

            if imageAspect > screenAspect {
                let height = finalFrame.width / imageAspect
                targetFrame = CGRect(
                    x: 0,
                    y: (finalFrame.height - height) / 2,
                    width: finalFrame.width,
                    height: height
                )
            } else {
                let width = finalFrame.height * imageAspect
                targetFrame = CGRect(
                    x: (finalFrame.width - width) / 2,
                    y: 0,
                    width: width,
                    height: finalFrame.height
                )
            }

            UIView.animate(withDuration: 0.21, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, animations: {
                snapshotView.frame = targetFrame
                snapshotView.layer.cornerRadius = 0
            })

            UIView.animate(withDuration: 0.15, delay: 0.1, options: .curveLinear, animations: {
                toView.alpha = 1
            }) { _ in
                snapshotView.removeFromSuperview()
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        } else {
            // Fade in
            toView.frame = finalFrame
            toView.alpha = 0
            container.addSubview(toView)

            UIView.animate(withDuration: 0.25, animations: {
                toView.alpha = 1
            }) { _ in
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        }
    }
}

// MARK: - Close Transition

final class GalleryCloseTransition: NSObject, UIViewControllerAnimatedTransitioning {

    private let sourceFrame: CGRect?

    init(sourceFrame: CGRect?) {
        self.sourceFrame = sourceFrame
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.21
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        // Simple fade out (swipe-to-dismiss handles the complex animation)
        UIView.animate(withDuration: 0.21, animations: {
            fromView.alpha = 0
        }) { _ in
            fromView.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
