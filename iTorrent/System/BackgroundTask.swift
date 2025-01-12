//
//  BackgroundTask.swift
//  iTorrent
//
//  Created by Daniil Vinogradov on 19.05.2018.
//  Copyright © 2018  XITRIX. All rights reserved.
//

import AVFoundation
import CoreLocation

#if TRANSMISSION
import ITorrentTransmissionFramework
#else
import ITorrentFramework
#endif

class BackgroundTask {
    public static let shared = BackgroundTask()
    var backgrounding: Bool {
        currentBackgroundMode != nil
    }

    private var player: AVAudioPlayer?

    private var locationManager = CLLocationManager()
    private var currentBackgroundMode: BackgroundTask.Mode?

    func stopBackgroundTask() {
        if let currentBackgroundMode {
            switch currentBackgroundMode {
            case .audio:
                stopWithAudio()
            case .location:
                stopWithLocation()
            }
        }

        currentBackgroundMode = nil
    }

    func startBackground() -> Bool {
        if UserPreferences.background,
           Core.shared.torrents.values.contains(where: { status -> Bool in
               BackgroundTask.getBackgroundConditions(status)
           })
        {
            startBackgroundTask()
            return true
        }
        return false
    }

    func checkToStopBackground() {
        if backgrounding {
            if !Core.shared.torrents.values.contains(where: { BackgroundTask.getBackgroundConditions($0) }) {
                Core.shared.saveTorrents()
                stopBackgroundTask()
            }
        }
    }

    static func getBackgroundConditions(_ status: TorrentModel) -> Bool {
        // state conditions
        (status.displayState == .downloading ||
            status.displayState == .metadata ||
            status.displayState == .hashing ||
            (status.displayState == .seeding &&
                UserPreferences.backgroundSeedKey &&
                status.seedMode) ||
            (UserPreferences.ftpKey &&
                UserPreferences.ftpBackgroundKey)) &&
            // zero speed limit conditions
            ((UserPreferences.zeroSpeedLimit > 0 &&
                    Core.shared.torrentsUserData[status.hash]?.zeroSpeedTimeCounter ?? 0 < UserPreferences.zeroSpeedLimit) ||
                UserPreferences.zeroSpeedLimit == 0)
    }
}

extension BackgroundTask {
    enum Mode: Codable {
        case audio
        case location
    }
}

extension BackgroundTask.Mode {
    var name: String {
        switch self {
        case .audio:
            return "BackgroundTask.Mode.Audio".localized
        case .location:
            return "BackgroundTask.Mode.Location".localized
        }
    }
}

private extension BackgroundTask {
    func startBackgroundTask() {
        if !backgrounding {
            switch UserPreferences.backgroundMode {
            case .audio:
                startWithAudio()
            case .location:
                startWithLocation()
            }
        }
    }
}

// MARK: - Location background stuff
private extension BackgroundTask {
    func startWithLocation() {
        currentBackgroundMode = .location
        if #available(iOS 14.0, *) {
            locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        }
        locationManager.requestWhenInUseAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        locationManager.showsBackgroundLocationIndicator = false
    }

    func stopWithLocation() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - Audio background stuff
private extension BackgroundTask {
    func startWithAudio() {
        currentBackgroundMode = .audio
        NotificationCenter.default.addObserver(self, selector: #selector(interruptedAudio), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        playAudio()
    }

    func stopWithAudio() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        player?.stop()
    }

    @objc func interruptedAudio(_ notification: Notification) {
        if notification.name == AVAudioSession.interruptionNotification,
           let info = notification.userInfo
        {
            var intValue = 0
            let key = info[AVAudioSessionInterruptionTypeKey] as AnyObject
            key.getValue(&intValue)
            if intValue == 1 { playAudio() }
        }
    }

    func playAudio() {
        do {
            let bundle = Bundle.main.path(forResource: "3", ofType: "wav")
            let alertSound = URL(fileURLWithPath: bundle!)
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            try player = AVAudioPlayer(contentsOf: alertSound)

            player?.numberOfLoops = -1
            player?.volume = 0.01
            player?.prepareToPlay()
            player?.play()
        } catch {
            print(error)
        }
    }
}
