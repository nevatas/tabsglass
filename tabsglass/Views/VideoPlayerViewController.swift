//
//  VideoPlayerViewController.swift
//  tabsglass
//
//  Fullscreen video player using AVPlayerViewController
//

import AVKit
import UIKit

final class VideoPlayerViewController: UIViewController {
    private let videoURL: URL
    private var player: AVPlayer?
    private var playerVC: AVPlayerViewController?

    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
    }

    private func setupPlayer() {
        player = AVPlayer(url: videoURL)

        let playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.showsPlaybackControls = true

        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.didMove(toParent: self)

        self.playerVC = playerVC

        // Add close button
        setupCloseButton()

        // Start playback
        player?.play()
    }

    private func setupCloseButton() {
        let closeButton = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Add shadow for visibility
        closeButton.layer.shadowColor = UIColor.black.cgColor
        closeButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        closeButton.layer.shadowOpacity = 0.5
        closeButton.layer.shadowRadius = 2

        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func closeTapped() {
        player?.pause()
        dismiss(animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }
}
