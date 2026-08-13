package com.uuvpn.pro.data.repository

import com.uuvpn.pro.data.local.NodeDao
import com.uuvpn.pro.data.local.PrefsManager
import com.uuvpn.pro.data.model.NodeModel
import com.uuvpn.pro.data.remote.XboardApiService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 节点仓库 — 获取/缓存/测速
 */
@Singleton
class NodeRepository @Inject constructor(
    private val apiService: XboardApiService,
    private val nodeDao: NodeDao,
    private val prefs: PrefsManager,
) {
    /** UDP 协议列表 — 不做 TCP ping */
    private val udpProtocols = setOf("hysteria", "hysteria2", "tuic")

    /**
     * 从远端获取节点 → 缓存到 Room
     */
    suspend fun fetchNodes(): Result<List<NodeModel>> {
        val result = apiService.fetchNodes()
        result.onSuccess { nodes ->
            nodeDao.deleteAll()
            nodeDao.insertAll(nodes)
        }
        return result
    }

    /**
     * 从缓存获取节点
     */
    suspend fun getCachedNodes(): List<NodeModel> {
        return nodeDao.getAllNodes()
    }

    /**
     * 获取所有区域
     */
    suspend fun getAllRegions(): List<String> {
        return nodeDao.getAllRegions()
    }

    /**
     * 根据 ID 获取节点
     */
    suspend fun getNodeById(id: Int): NodeModel? {
        return nodeDao.getNodeById(id)
    }

    /**
     * TCP Ping 单个节点
     */
    suspend fun pingNode(node: NodeModel): Int = withContext(Dispatchers.IO) {
        if (node.host.isBlank()) return@withContext -1

        // UDP 协议只检查在线状态
        if (udpProtocols.contains(node.type.lowercase())) {
            return@withContext if (node.isOnline) 1 else 999
        }

        try {
            val start = System.currentTimeMillis()
            val socket = Socket()
            socket.connect(InetSocketAddress(node.host, node.port), 3000)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            socket.close()
            elapsed
        } catch (e: Exception) {
            999
        }
    }

    /**
     * 更新节点延迟到数据库
     */
    suspend fun updatePing(nodeId: Int, pingMs: Int) {
        nodeDao.updatePing(nodeId, pingMs)
    }

    /**
     * 保存选中的节点
     */
    suspend fun setSelectedNode(nodeId: Int) {
        prefs.setSelectedNodeId(nodeId)
    }
}
