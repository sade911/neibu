package com.uuvpn.pro.data.model

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 节点模型 — 同时作为 Room Entity
 */
@Entity(tableName = "nodes")
data class NodeModel(
    @PrimaryKey val id: Int,
    val name: String,
    val type: String,           // vless / trojan / vmess / hysteria2 / shadowsocks / tuic / wireguard
    val host: String,
    val port: Int,
    val serverPort: Int,
    val rate: Double = 1.0,
    val flag: String = "UN",    // 国家代码 HK / JP / US ...
    val tags: String = "",      // 逗号分隔标签
    val rawConfigJson: String = "{}",
    val isOnline: Boolean = false,
    val pingMs: Int? = null,
) {
    val displayType: String get() = type.uppercase()
    val regionTag: String get() = flag.ifEmpty { "UN" }
    val tagList: List<String> get() = tags.split(",").filter { it.isNotBlank() }

    companion object {
        private val FLAG_MAP = mapOf(
            "香港" to "HK", "日本" to "JP", "美国" to "US", "新加坡" to "SG",
            "台湾" to "TW", "韩国" to "KR", "英国" to "GB", "德国" to "DE",
            "法国" to "FR", "加拿大" to "CA", "澳大利亚" to "AU", "印度" to "IN",
            "印度尼西亚" to "ID", "俄罗斯" to "RU", "巴西" to "BR", "荷兰" to "NL",
            "土耳其" to "TR", "马来西亚" to "MY", "泰国" to "TH", "越南" to "VN",
            "菲律宾" to "PH", "阿根廷" to "AR",
            "Hong Kong" to "HK", "Japan" to "JP", "USA" to "US", "United States" to "US",
            "Singapore" to "SG", "Taiwan" to "TW", "Korea" to "KR", "UK" to "GB",
            "Germany" to "DE", "France" to "FR", "Canada" to "CA", "Australia" to "AU",
        )

        fun getFlagFromName(name: String): String {
            for ((key, value) in FLAG_MAP) {
                if (name.contains(key, ignoreCase = true)) return value
            }
            return "UN"
        }
    }
}
