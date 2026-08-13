package com.uuvpn.pro.data.local

import androidx.room.*
import com.uuvpn.pro.data.model.NodeModel

@Dao
interface NodeDao {

    @Query("SELECT * FROM nodes ORDER BY name ASC")
    suspend fun getAllNodes(): List<NodeModel>

    @Query("SELECT * FROM nodes WHERE flag = :flag ORDER BY name ASC")
    suspend fun getNodesByRegion(flag: String): List<NodeModel>

    @Query("SELECT * FROM nodes WHERE id = :id")
    suspend fun getNodeById(id: Int): NodeModel?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(nodes: List<NodeModel>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(node: NodeModel)

    @Query("UPDATE nodes SET pingMs = :pingMs WHERE id = :id")
    suspend fun updatePing(id: Int, pingMs: Int)

    @Query("DELETE FROM nodes")
    suspend fun deleteAll()

    @Query("SELECT DISTINCT flag FROM nodes ORDER BY flag ASC")
    suspend fun getAllRegions(): List<String>
}
