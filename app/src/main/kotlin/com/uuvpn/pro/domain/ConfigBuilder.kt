package com.uuvpn.pro.domain

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.reflect.TypeToken
import com.uuvpn.pro.data.model.NodeModel

/**
 * sing-box JSON 配置构建器
 *
 * 从 Flutter config_builder.dart 完整移植
 * 支持: VLESS / Trojan / VMess / Hysteria2 / Shadowsocks / TUIC / WireGuard
 */
object ConfigBuilder {

    private val gson: Gson = GsonBuilder().setPrettyPrinting().create()

    /**
     * 构建完整的 sing-box 配置 JSON
     */
    fun build(
        node: NodeModel,
        uuid: String,
        httpPort: Int = 7890,
        socksPort: Int = 7891,
        logLevel: String = "warn",
        routeMode: String = "bypass_cn",   // bypass_cn / global
        dnsMode: String = "auto",
    ): String {
        val outbound = buildOutbound(node, uuid)

        val config = mutableMapOf<String, Any>(
            "log" to mapOf("level" to logLevel, "timestamp" to true),
            "dns" to buildDns(routeMode),
            "inbounds" to buildInbounds(httpPort),
            "outbounds" to listOf(
                outbound,
                mapOf("type" to "direct", "tag" to "direct"),
                mapOf("type" to "block", "tag" to "block"),
                mapOf("type" to "dns", "tag" to "dns-out"),
            ),
            "route" to buildRoute(routeMode),
            "experimental" to mapOf(
                "clash_api" to mapOf("external_controller" to "127.0.0.1:9090"),
                "cache_file" to mapOf("enabled" to true),
            ),
        )

        return gson.toJson(config)
    }

    // ============================================================
    // DNS
    // ============================================================

    private fun buildDns(routeMode: String): Map<String, Any> {
        val servers = mutableListOf(
            mapOf("tag" to "remote-dns", "address" to "https://8.8.8.8/dns-query", "detour" to "proxy"),
            mapOf("tag" to "local-dns", "address" to "https://223.5.5.5/dns-query", "detour" to "direct"),
            mapOf("tag" to "block-dns", "address" to "rcode://success"),
        )

        val rules = mutableListOf<Map<String, Any>>(
            mapOf("outbound" to listOf("any"), "server" to "local-dns"),
            mapOf("clash_mode" to "Direct", "server" to "local-dns"),
            mapOf("clash_mode" to "Global", "server" to "remote-dns"),
        )

        if (routeMode == "bypass_cn") {
            rules.add(mapOf("rule_set" to "geosite-cn", "server" to "local-dns"))
        }

        return mapOf(
            "servers" to servers,
            "rules" to rules,
            "strategy" to "prefer_ipv4",
        )
    }

    // ============================================================
    // Inbounds
    // ============================================================

    private fun buildInbounds(httpPort: Int): List<Map<String, Any>> {
        return listOf(
            mapOf(
                "type" to "tun",
                "tag" to "tun-in",
                "inet4_address" to "172.19.0.1/30",
                "inet6_address" to "fdfe:dcba:9876::1/126",
                "auto_route" to true,
                "strict_route" to true,
                "stack" to "system",
                "sniff" to true,
                "sniff_override_destination" to true,
            ),
            mapOf(
                "type" to "mixed",
                "tag" to "mixed-in",
                "listen" to "127.0.0.1",
                "listen_port" to httpPort,
            ),
        )
    }

    // ============================================================
    // Route
    // ============================================================

    private fun buildRoute(routeMode: String): Map<String, Any> {
        val rules = mutableListOf<Map<String, Any>>(
            mapOf("protocol" to "dns", "outbound" to "dns-out"),
            mapOf("clash_mode" to "Direct", "outbound" to "direct"),
            mapOf("clash_mode" to "Global", "outbound" to "proxy"),
        )

        if (routeMode == "bypass_cn") {
            rules.add(mapOf("rule_set" to "geoip-cn", "outbound" to "direct"))
            rules.add(mapOf("rule_set" to "geosite-cn", "outbound" to "direct"))
        }
        rules.add(mapOf("ip_is_private" to true, "outbound" to "direct"))

        val result = mutableMapOf<String, Any>(
            "auto_detect_interface" to true,
            "final" to "proxy",
            "rules" to rules,
        )

        if (routeMode == "bypass_cn") {
            result["rule_set"] = listOf(
                mapOf(
                    "tag" to "geoip-cn",
                    "type" to "remote",
                    "format" to "binary",
                    "url" to "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
                    "download_detour" to "proxy",
                ),
                mapOf(
                    "tag" to "geosite-cn",
                    "type" to "remote",
                    "format" to "binary",
                    "url" to "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
                    "download_detour" to "proxy",
                ),
            )
        }

        return result
    }

    // ============================================================
    // Outbound Builder
    // ============================================================

    private fun buildOutbound(node: NodeModel, uuid: String): Map<String, Any> {
        val raw = parseRawConfig(node.rawConfigJson)
        val ps = getProtocolSettings(raw)

        return when (node.type.lowercase()) {
            "vless" -> buildVless(node, uuid, ps)
            "trojan" -> buildTrojan(node, uuid, ps)
            "vmess" -> buildVmess(node, uuid, ps)
            "hysteria", "hysteria2" -> buildHysteria2(node, uuid, ps)
            "shadowsocks" -> buildShadowsocks(node, uuid, ps, raw)
            "tuic" -> buildTuic(node, uuid, ps)
            "wireguard" -> buildWireguard(node, uuid, ps)
            else -> mapOf("type" to "direct", "tag" to "proxy")
        }
    }

    // ===== VLESS =====
    private fun buildVless(node: NodeModel, uuid: String, ps: Map<String, Any?>): Map<String, Any> {
        val out = mutableMapOf<String, Any>(
            "type" to "vless",
            "tag" to "proxy",
            "server" to node.host,
            "server_port" to node.serverPort,
            "uuid" to uuid,
        )

        val flow = ps["flow"]?.toString() ?: ""
        if (flow.isNotEmpty()) out["flow"] = flow

        // Network/Transport
        val network = ps["network"]?.toString() ?: "tcp"
        addTransport(out, network, ps)

        // TLS / Reality
        addTlsOrReality(out, ps)

        return out
    }

    // ===== Trojan =====
    private fun buildTrojan(node: NodeModel, uuid: String, ps: Map<String, Any?>): Map<String, Any> {
        val out = mutableMapOf<String, Any>(
            "type" to "trojan",
            "tag" to "proxy",
            "server" to node.host,
            "server_port" to node.serverPort,
            "password" to uuid,
        )

        val network = ps["network"]?.toString() ?: "tcp"
        addTransport(out, network, ps)
        addTlsOrReality(out, ps, defaultTls = true)

        return out
    }

    // ===== VMess =====
    private fun buildVmess(node: NodeModel, uuid: String, ps: Map<String, Any?>): Map<String, Any> {
        val out = mutableMapOf<String, Any>(
            "type" to "vmess",
            "tag" to "proxy",
            "server" to node.host,
            "server_port" to node.serverPort,
            "uuid" to uuid,
            "alter_id" to 0,
            "security" to "auto",
        )

        val network = ps["network"]?.toString() ?: "tcp"
        addTransport(out, network, ps)

        val tls = ps["tls"]
        if (tls != null && tls != 0 && tls != false) {
            out["tls"] = mapOf("enabled" to true, "insecure" to true)
        }

        return out
    }

    // ===== Hysteria2 =====
    private fun buildHysteria2(node: NodeModel, uuid: String, ps: Map<String, Any?>): Map<String, Any> {
        val out = mutableMapOf<String, Any>(
            "type" to "hysteria2",
            "tag" to "proxy",
            "server" to node.host,
            "server_port" to node.serverPort,
            "password" to uuid,
            "tls" to mapOf("enabled" to true, "insecure" to true),
        )

        @Suppress("UNCHECKED_CAST")
        val obfs = ps["obfs"] as? Map<String, Any?> ?: emptyMap()
        if (obfs["open"] == true) {
            out["obfs"] = mapOf(
                "type" to (obfs["type"]?.toString() ?: "salamander"),
                "password" to (obfs["password"]?.toString() ?: ""),
            )
        }

        return out
    }

    // ===== Shadowsocks =====
    private fun buildShadowsocks(
        node: NodeModel, uuid: String,
        ps: Map<String, Any?>, raw: Map<String, Any?>,
    ): Map<String, Any> {
        val cipher = ps["cipher"]?.toString() ?: "aes-256-gcm"
        val password = if (cipher.startsWith("2022")) {
            raw["server_key"]?.toString() ?: uuid
        } else {
            uuid
        }

        return mapOf(
            "type" to "shadowsocks",
            "tag" to "proxy",
            "server" to node.host,
            "server_port" to node.serverPort,
            "method" to cipher,
            "password" to password,
        )
    }

    // ===== TUIC =====
    private fun buildTuic(node: NodeModel, uuid: String, ps: Map<String, Any?>): Map<String, Any> {
        return mapOf(
            "type" to "tuic",
            "tag" to "proxy",
            "server" to node.host,
            "server_port" to node.serverPort,
            "uuid" to uuid,
            "password" to uuid,
            "congestion_control" to (ps["congestion_control"]?.toString() ?: "bbr"),
            "udp_relay_mode" to (ps["udp_relay_mode"]?.toString() ?: "native"),
            "tls" to mapOf(
                "enabled" to true,
                "insecure" to true,
                "alpn" to listOf("h3"),
            ),
        )
    }

    // ===== WireGuard =====
    private fun buildWireguard(node: NodeModel, uuid: String, ps: Map<String, Any?>): Map<String, Any> {
        val out = mutableMapOf<String, Any>(
            "type" to "wireguard",
            "tag" to "proxy",
            "server" to node.host,
            "server_port" to node.serverPort,
            "private_key" to (ps["private_key"]?.toString() ?: ""),
            "peer_public_key" to (ps["peer_public_key"]?.toString() ?: ps["public_key"]?.toString() ?: ""),
            "reserved" to (ps["reserved"] ?: listOf(0, 0, 0)),
            "mtu" to (ps["mtu"] ?: 1280),
        )

        val localAddress = ps["local_address"]?.toString()
        if (localAddress != null) {
            out["local_address"] = listOf(localAddress)
        } else {
            out["local_address"] = listOf("10.0.0.2/32")
        }

        val preSharedKey = ps["pre_shared_key"]?.toString()
        if (!preSharedKey.isNullOrEmpty()) {
            out["pre_shared_key"] = preSharedKey
        }

        return out
    }

    // ============================================================
    // Helpers
    // ============================================================

    private fun addTransport(
        out: MutableMap<String, Any>,
        network: String,
        ps: Map<String, Any?>,
    ) {
        @Suppress("UNCHECKED_CAST")
        val ns = ps["network_settings"] as? Map<String, Any?> ?: emptyMap()

        when (network) {
            "grpc" -> {
                out["transport"] = mapOf(
                    "type" to "grpc",
                    "service_name" to (ns["serviceName"] ?: ns["service_name"] ?: "grpc"),
                )
            }
            "ws" -> {
                out["transport"] = mapOf(
                    "type" to "ws",
                    "path" to (ns["path"]?.toString() ?: "/ws"),
                )
            }
            "h2", "http" -> {
                out["transport"] = mapOf(
                    "type" to "http",
                    "path" to (ns["path"]?.toString() ?: "/"),
                )
            }
        }
    }

    private fun addTlsOrReality(
        out: MutableMap<String, Any>,
        ps: Map<String, Any?>,
        defaultTls: Boolean = false,
    ) {
        @Suppress("UNCHECKED_CAST")
        val rs = ps["reality_settings"] as? Map<String, Any?> ?: emptyMap()

        if (rs.isNotEmpty()) {
            out["tls"] = mapOf(
                "enabled" to true,
                "server_name" to (rs["server_name"]?.toString() ?: "www.microsoft.com"),
                "utls" to mapOf("enabled" to true, "fingerprint" to "chrome"),
                "reality" to mapOf(
                    "enabled" to true,
                    "public_key" to (rs["public_key"]?.toString() ?: ""),
                    "short_id" to (rs["short_id"]?.toString() ?: ""),
                ),
            )
        } else {
            val tls = ps["tls"]
            if (defaultTls || (tls != null && tls != 0 && tls != false)) {
                out["tls"] = mapOf("enabled" to true, "insecure" to true)
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseRawConfig(json: String): Map<String, Any?> {
        return try {
            val type = object : TypeToken<Map<String, Any?>>() {}.type
            gson.fromJson(json, type) ?: emptyMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun getProtocolSettings(raw: Map<String, Any?>): Map<String, Any?> {
        return raw["protocolSettings"] as? Map<String, Any?>
            ?: raw["protocol_settings"] as? Map<String, Any?>
            ?: emptyMap()
    }
}
