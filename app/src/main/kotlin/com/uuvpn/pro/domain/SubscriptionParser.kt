package com.uuvpn.pro.domain

/**
 * 订阅内容解析器
 *
 * 从 Clash YAML / URI 中提取 UUID
 */
object SubscriptionParser {

    private val UUID_REGEX = Regex("uuid:\\s*([a-f0-9\\-]{36})", RegexOption.IGNORE_CASE)
    private val PWD_REGEX = Regex("password:\\s*([a-f0-9\\-]{36})", RegexOption.IGNORE_CASE)

    /**
     * 从订阅内容（Clash YAML）中提取 UUID
     */
    fun extractUuid(content: String): String? {
        return UUID_REGEX.find(content)?.groupValues?.get(1)
            ?: PWD_REGEX.find(content)?.groupValues?.get(1)
    }
}
