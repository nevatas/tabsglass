//
//  GalleryViewController.swift
//  tabsglass
//
//  Telegram-style fullscreen gallery viewer for photos
//

import UIKit

// MARK: - Gallery View Controller

final class GalleryViewController: UIViewController {

    // MARK: - Properties

    private let photos: [UIImage]
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

    init(photos: [UIImage], startIndex: Int, sourceFrame: CGRect?, sourceImage: UIImage?) {
        self.photos = photos
        self.currentIndex = startIndex
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
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
        guard photos.count > 1 else { return }

        pageControl.numberOfPages = photos.count
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

    private func makePageController(for index: Int) -> GalleryPageViewController {
        let vc = GalleryPageViewController(image: photos[index], index: index)
        vc.onZoomChange = { [weak self] isZoomed in
            self?.handleZoomChange(isZoomed)
        }
        vc.onSingleTap = { [weak self] in
            self?.toggleUI()
        }
        return vc
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
        guard let vc = viewController as? GalleryPageViewController else { return nil }
        let index = vc.index - 1
        guard index >= 0 else { return nil }
        return makePageController(for: index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? GalleryPageViewController else { return nil }
        let index = vc.index + 1
        guard index < photos.count else { return nil }
        return makePageController(for: index)
    }
}

// MARK: - UIPageViewControllerDelegate

extension GalleryViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let currentVC = pageViewController.viewControllers?.first as? GalleryPageViewController else { return }
        currentIndex = currentVC.index
        pageControl.currentPage = currentIndex
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

// MARK: - Gallery Page View Controller

final class GalleryPageViewController: UIViewController {

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
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
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

        let widthScale = view.bounds.width / image.size.width
        let heightScale = view.bounds.height / image.size.height
        let minScale = min(widthScale, heightScale)

        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * 3, 1.0)

        if scrollView.zoomScale < minScale {
            scrollView.zoomScale = minScale
        }

        // Update image view frame
        let scaledWidth = image.size.width * minScale
        let scaledHeight = image.size.height * minScale
        imageView.frame = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
        scrollView.contentSize = imageView.frame.size
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
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            // Zoom out
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            // Zoom in to tap location
            let location = gesture.location(in: imageView)
            let zoomRect = zoomRectForScale(scrollView.maximumZoomScale * 0.7, center: location)
            scrollView.zoom(to: zoomRect, animated: true)
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
        let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        onZoomChange?(isZoomed)
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
