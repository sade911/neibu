package com.uuvpn.pro.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.uuvpn.pro.data.model.NodeModel
import com.uuvpn.pro.data.repository.NodeRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import javax.inject.Inject

@HiltViewModel
class NodeViewModel @Inject constructor(
    private val nodeRepository: NodeRepository,
) : ViewModel() {

    private val _nodes = MutableStateFlow<List<NodeModel>>(emptyList())
    val nodes: StateFlow<List<NodeModel>> = _nodes.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isPinging = MutableStateFlow(false)
    val isPinging: StateFlow<Boolean> = _isPinging.asStateFlow()

    private val _regions = MutableStateFlow<List<String>>(emptyList())
    val regions: StateFlow<List<String>> = _regions.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _selectedRegion = MutableStateFlow("全部")
    val selectedRegion: StateFlow<String> = _selectedRegion.asStateFlow()

    private val _sortMode = MutableStateFlow(SortMode.DEFAULT)
    val sortMode: StateFlow<SortMode> = _sortMode.asStateFlow()

    /** 过滤后的节点列表 */
    val filteredNodes: StateFlow<List<NodeModel>> = combine(
        _nodes, _searchQuery, _selectedRegion, _sortMode
    ) { nodes, query, region, sort ->
        var filtered = nodes

        // 区域过滤
        if (region != "全部") {
            filtered = filtered.filter { it.flag == region }
        }

        // 搜索
        if (query.isNotBlank()) {
            val q = query.lowercase()
            filtered = filtered.filter {
                it.name.lowercase().contains(q) || it.type.lowercase().contains(q)
            }
        }

        // 排序
        when (sort) {
            SortMode.PING -> filtered.sortedBy { it.pingMs ?: Int.MAX_VALUE }
            SortMode.NAME -> filtered.sortedBy { it.name }
            SortMode.DEFAULT -> filtered
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), emptyList())

    init {
        loadCachedNodes()
        fetchNodes()
    }

    private fun loadCachedNodes() {
        viewModelScope.launch {
            val cached = nodeRepository.getCachedNodes()
            if (cached.isNotEmpty()) {
                _nodes.value = cached
                updateRegions(cached)
            }
        }
    }

    fun fetchNodes() {
        viewModelScope.launch {
            _isLoading.value = true
            nodeRepository.fetchNodes().onSuccess { nodes ->
                _nodes.value = nodes
                updateRegions(nodes)
            }
            _isLoading.value = false
        }
    }

    /**
     * 并行 ping 所有节点（每批 10 个并发，避免阻塞太久）
     */
    fun pingAllNodes() {
        viewModelScope.launch {
            _isPinging.value = true
            try {
                val currentNodes = _nodes.value
                // 分批并行 ping，每批最多 10 个
                val batchSize = 10
                val updatedNodes = currentNodes.toMutableList()

                currentNodes.chunked(batchSize).forEachIndexed { batchIndex, batch ->
                    supervisorScope {
                        val results = batch.map { node ->
                            async {
                                val ping = nodeRepository.pingNode(node)
                                nodeRepository.updatePing(node.id, ping)
                                node.id to ping
                            }
                        }.awaitAll()

                        // 更新到列表
                        results.forEach { (nodeId, ping) ->
                            val index = updatedNodes.indexOfFirst { it.id == nodeId }
                            if (index >= 0) {
                                updatedNodes[index] = updatedNodes[index].copy(pingMs = ping)
                            }
                        }

                        // 每批完成后更新 UI
                        _nodes.value = updatedNodes.toList()
                    }
                }
            } finally {
                _isPinging.value = false
            }
        }
    }

    fun setSearchQuery(query: String) {
        _searchQuery.value = query
    }

    fun setSelectedRegion(region: String) {
        _selectedRegion.value = region
    }

    fun setSortMode(mode: SortMode) {
        _sortMode.value = mode
    }

    private fun updateRegions(nodes: List<NodeModel>) {
        _regions.value = nodes.map { it.flag }.distinct().sorted()
    }
}

enum class SortMode {
    DEFAULT, PING, NAME
}
