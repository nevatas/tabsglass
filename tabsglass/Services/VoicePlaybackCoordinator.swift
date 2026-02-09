//
//  VoicePlaybackCoordinator.swift
//  tabsglass
//

import Foundation

protocol VoicePlaybackControlling: AnyObject {
    func stopPlaybackFromCoordinator()
}

@MainActor
final class VoicePlaybackCoordinator {
    static let shared = VoicePlaybackCoordinator()

    private weak var activeController: VoicePlaybackControlling?

    private init() {}

    func activate(_ controller: VoicePlaybackControlling) {
        if activeController !== controller {
            activeController?.stopPlaybackFromCoordinator()
            activeController = controller
        }
    }

    func deactivate(_ controller: VoicePlaybackControlling) {
        if activeController === controller {
            activeController = nil
        }
    }
}
