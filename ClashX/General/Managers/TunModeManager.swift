//
//  TunModeManager.swift
//  ClashX
//
//  TUN mode for the in-process clash core.
//
//  Creating a utun device and editing the routing table require root, so the
//  embedded core cannot do it itself (mihomo silently reverts tun.enable when
//  utun creation fails). Instead the privileged helper creates the utun,
//  assigns the address and installs the routes, then hands the file
//  descriptor back over XPC. Because the core runs inside this process, the
//  fd can be passed to it via the regular PATCH /configs `file-descriptor`
//  option. The kernel destroys the interface and purges its routes when the
//  fd closes, so a crash of ClashX cleans up by itself.
//

import Foundation
import RxSwift

class TunModeManager {
    static let shared = TunModeManager()

    private let disposeBag = DisposeBag()
    private var operating = false

    private init() {}

    // MARK: - Public

    /// Re-applies the persisted TUN choice once the core has loaded a config
    /// and the privileged helper is confirmed installed.
    func setupAtLaunch() {
        Observable.combineLatest(
            PrivilegedHelperManager.shared.isHelperCheckFinished.filter { $0 }.take(1),
            ConfigManager.shared.currentConfigVariable.filter { $0 != nil }.take(1)
        )
        .take(1)
        .observe(on: MainScheduler.instance)
        .subscribe(onNext: { [weak self] _ in
            self?.reapplyIfNeeded()
        })
        .disposed(by: disposeBag)
    }

    /// Config reloads run executor.ApplyConfig, which resets tun to whatever
    /// the config file says (usually disabled) and closes our fd. Call this
    /// after every successful reload to bring TUN back up.
    func reapplyIfNeeded() {
        guard Settings.tunMode, ConfigManager.shared.isRunning,
              RemoteControlManager.selectConfig == nil else { return }
        ApiRequest.getConfig { [weak self] config in
            // Re-check the setting: the user may have toggled TUN off while
            // the GET was in flight.
            guard Settings.tunMode, let config = config, config.tun?.enable != true else { return }
            self?.setTunMode(enable: true) { error in
                if let error = error {
                    Logger.log("Reapply TUN mode failed: \(error)", level: .warning)
                }
                (NSApplication.shared.delegate as? AppDelegate)?.syncConfig()
            }
        }
    }

    /// Completion is called on the main queue with nil on success or a
    /// human-readable error message.
    func setTunMode(enable: Bool, completion: @escaping (String?) -> Void) {
        let finish: (String?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                self?.operating = false
                completion(error)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.operating else {
                // Reject directly — `finish` would clear the `operating`
                // flag owned by the still-running operation.
                completion(NSLocalizedString("TUN operation already in progress", comment: ""))
                return
            }
            self.operating = true

            guard ConfigManager.shared.isRunning else {
                finish(NSLocalizedString("Clash core is not running", comment: ""))
                return
            }

            // With an external controller the core lives in another process
            // (possibly rooted), where our fd would be meaningless — fall
            // back to a plain enable PATCH and let that core handle tun
            // itself.
            guard RemoteControlManager.selectConfig == nil else {
                ApiRequest.updateTunMode(enable: enable) { success in
                    finish(success ? nil : NSLocalizedString("Failed to update TUN mode", comment: ""))
                }
                return
            }

            if enable {
                self.enableTun(finish: finish)
            } else {
                ApiRequest.updateTun(params: ["enable": false]) { success in
                    finish(success ? nil : NSLocalizedString("Failed to update TUN mode", comment: ""))
                }
            }
        }
    }

    // MARK: - Private

    private func enableTun(finish: @escaping (String?) -> Void) {
        // The core's tun inet4-address is not settable over the REST API
        // (it derives from the fake-ip range), so read it and configure the
        // interface to match.
        ApiRequest.getConfig { [weak self] config in
            guard let config = config else {
                finish(NSLocalizedString("Failed to read Clash config", comment: ""))
                return
            }
            let inet4 = config.tun?.inet4Address?.first ?? "198.18.0.1/30"
            // After a config reload the core can advertise an inet6-address
            // even though the user never enabled IPv6 in ClashX; routing v6
            // into the tun while the resolver has IPv6 off would blackhole
            // it, so gate on the user's setting.
            let inet6 = Settings.enableIPV6 ? config.tun?.inet6Address?.first : nil
            self?.requestTunFd(inet4: inet4, inet6: inet6) { fd, error in
                guard fd >= 0 else {
                    finish(error ?? NSLocalizedString("Failed to create TUN interface", comment: ""))
                    return
                }
                self?.attachTun(fd: fd, finish: finish)
            }
        }
    }

    /// Asks the helper for a configured utun and returns a duplicated fd
    /// owned by this process (-1 on failure). Completion may be called on
    /// any queue.
    private func requestTunFd(inet4: String, inet6: String?, completion: @escaping (Int32, String?) -> Void) {
        var called = false
        let callOnce: (Int32, String?) -> Void = { fd, error in
            DispatchQueue.main.async {
                guard !called else {
                    if fd >= 0 { close(fd) }
                    return
                }
                called = true
                completion(fd, error)
            }
        }

        guard let helper = PrivilegedHelperManager.shared.helper(failture: {
            callOnce(-1, NSLocalizedString("Connection to the privileged helper failed. Try reinstalling the helper in Settings - Debug.", comment: ""))
        }) else {
            callOnce(-1, NSLocalizedString("Connection to the privileged helper failed. Try reinstalling the helper in Settings - Debug.", comment: ""))
            return
        }

        helper.startTun(withInet4Address: inet4, inet6Address: inet6, mtu: 1500) { handle, _, error in
            guard let handle = handle else {
                callOnce(-1, error)
                return
            }
            // The NSFileHandle closes its fd on dealloc; hand the core an
            // independent duplicate so ownership is unambiguous.
            let fd = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
            guard fd >= 0 else {
                callOnce(-1, "dup tun fd failed: \(String(cString: strerror(errno)))")
                return
            }
            callOnce(fd, nil)
        }
    }

    private func attachTun(fd: Int32, finish: @escaping (String?) -> Void) {
        // auto-route stays off (the helper already installed the routes;
        // sing-tun could not install them unprivileged anyway), while
        // auto-detect-interface keeps outbound connections bound to the
        // physical interface so tun-captured traffic cannot loop.
        let params: [String: Any] = [
            "enable": true,
            "file-descriptor": Int(fd),
            "auto-route": false,
            "auto-detect-interface": true,
            "dns-hijack": ["any:53"],
            "mtu": 1500
        ]
        ApiRequest.updateTun(params: params) { success in
            guard success else {
                // The core never decoded the fd; it is still ours to close.
                close(fd)
                finish(NSLocalizedString("Failed to update TUN mode", comment: ""))
                return
            }
            // The PATCH returns 204 even when the tun stack fails to start;
            // the core reverts tun.enable in that case, so read it back.
            // Past this point the fd belongs to the core: on late start
            // failures it has already closed it, so closing the (possibly
            // recycled) number here could kill an unrelated descriptor.
            ApiRequest.getConfig { config in
                guard let config = config else {
                    Logger.log("TUN enabled but state verification failed", level: .warning)
                    finish(nil)
                    return
                }
                if config.tun?.enable == true {
                    finish(nil)
                } else {
                    finish(NSLocalizedString("Clash core failed to start TUN, check logs", comment: ""))
                }
            }
        }
    }
}
