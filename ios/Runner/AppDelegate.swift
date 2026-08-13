import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var vpnManager: NETunnelProviderManager?
    private var channel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController

        channel = FlutterMethodChannel(
            name: "com.uuvpn/singbox",
            binaryMessenger: controller.binaryMessenger
        )

        channel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "start":
                if let args = call.arguments as? [String: Any],
                   let config = args["config"] as? String {
                    self?.startVpn(config: config, result: result)
                } else {
                    result(FlutterError(code: "NO_CONFIG", message: "Config is null", details: nil))
                }
            case "stop":
                self?.stopVpn(result: result)
            case "getStatus":
                self?.getStatus(result: result)
            case "getTrafficStats":
                result(["upload": 0, "download": 0])
            case "requestVpnPermission":
                result(true) // iOS handles VPN permission via system dialog
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - VPN Management

    private func startVpn(config: String, result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                result(FlutterError(code: "VPN_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()
            self?.vpnManager = manager

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.uuvpn.uuvpn-ios.PacketTunnel"
            proto.serverAddress = "UUVPN PRO"
            proto.providerConfiguration = ["config": config]

            manager.protocolConfiguration = proto
            manager.localizedDescription = "UUVPN PRO"
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    result(FlutterError(code: "VPN_SAVE_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                manager.loadFromPreferences { error in
                    if let error = error {
                        result(FlutterError(code: "VPN_LOAD_ERROR", message: error.localizedDescription, details: nil))
                        return
                    }

                    do {
                        let session = manager.connection as! NETunnelProviderSession
                        try session.startTunnel(options: ["config": config as NSObject])
                        result(true)
                    } catch {
                        result(FlutterError(code: "VPN_START_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func stopVpn(result: @escaping FlutterResult) {
        vpnManager?.connection.stopVPNTunnel()
        result(true)
    }

    private func getStatus(result: @escaping FlutterResult) {
        guard let manager = vpnManager else {
            result("stopped")
            return
        }

        switch manager.connection.status {
        case .connected:
            result("running")
        case .connecting:
            result("connecting")
        case .disconnecting:
            result("disconnecting")
        default:
            result("stopped")
        }
    }
}
