package com.uuvpn.pro.data.model

/**
 * 套餐模型
 */
data class PlanModel(
    val id: Int,
    val name: String,
    val transferEnable: Long = 0,
    val monthPrice: Double? = null,
)
