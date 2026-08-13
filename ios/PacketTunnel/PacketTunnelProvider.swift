import NetworkExtension

/// NEPacketTunnelProvider — sing-box VPN 隧道
///
/// 集成 libbox 后，在 startTunnel 中初始化 sing-box 引擎
/// 目前为占位实现，建立基本的隧道框架
class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // 从 options 或 protocolConfiguration 获取配置
        let config: String
        if let opts = options, let c = opts["config"] as? String {
            config = c
        } else if let proto = protocolConfiguration as? NETunnelProviderProtocol,
                  let providerConfig = proto.providerConfiguration,
                  let c = providerConfig["config"] as? String {
            config = c
        } else {
            completionHandler(NSError(domain: "com.uuvpn", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No config provided"]))
            return
        }

        // 配置 TUN 网络设置
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        // IPv4
        settings.ipv4Settings = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]

        // DNS
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])

        // MTU
        settings.mtu = NSNumber(value: 9000)

        // 应用网络设置
        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                completionHandler(error)
                return
            }

            // TODO: 集成 libbox 后，在这里启动 sing-box 引擎
            // LibBox.start(config, fd: self.packetFlow.value(forKey: "socket") as! Int32)

            NSLog("[PacketTunnel] Tunnel started successfully")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // TODO: 集成 libbox 后，停止 sing-box 引擎
        // LibBox.stop()

        NSLog("[PacketTunnel] Tunnel stopped, reason: \(reason)")
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // 处理来自主 App 的消息（例如获取流量统计）
        if let message = String(data: messageData, encoding: .utf8) {
            NSLog("[PacketTunnel] Received message: \(message)")
        }
        completionHandler?(nil)
    }
}
