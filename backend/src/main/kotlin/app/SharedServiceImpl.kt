package app

import app.generated.GetMetricsRequest
import app.generated.MetricsResponse
import app.generated.MetricsServiceGrpcKt
import app.generated.metricsResponse
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.*

class SharedServiceImpl(private val vmUrl: String) :
    MetricsServiceGrpcKt.MetricsServiceCoroutineImplBase() {

    private val http = HttpClient(CIO) {
        install(ContentNegotiation) { json() }
        expectSuccess = false
    }

    override suspend fun getMetrics(request: GetMetricsRequest): MetricsResponse =
        fetchFromVictoriaMetrics()

    // Server sends a snapshot every 15 seconds to keep the Cloudflare Tunnel
    // connection alive (idle timeout ≈ 100s).
    override fun streamMetrics(request: GetMetricsRequest): Flow<MetricsResponse> = flow {
        while (true) {
            emit(fetchFromVictoriaMetrics())
            delay(15_000)
        }
    }

    private suspend fun fetchFromVictoriaMetrics(): MetricsResponse {
        return try {
            val queries = mapOf(
                "tps"         to "minecraft_tps",
                "players"     to "minecraft_players_online",
                "playersMax"  to "minecraft_players_max",
                "memUsed"     to "minecraft_jvm_memory_used_bytes",
                "memMax"      to "minecraft_jvm_memory_max_bytes",
                "cpu"         to "minecraft_cpu_usage_percent",
                "uptime"      to "minecraft_uptime_seconds",
            )

            val results = queries.mapValues { (_, query) ->
                val res: String = http.get("$vmUrl/api/v1/query") {
                    parameter("query", query)
                }.body()
                parseVmScalar(res)
            }

            metricsResponse {
                isOnline      = true
                serverName    = "Tagomori"
                version       = queryVersion()
                tps           = results["tps"] ?: 0.0
                playersOnline = (results["players"] ?: 0.0).toInt()
                playersMax    = (results["playersMax"] ?: 0.0).toInt()
                memoryUsedMb  = ((results["memUsed"] ?: 0.0) / 1_048_576).toInt()
                memoryMaxMb   = ((results["memMax"] ?: 0.0) / 1_048_576).toInt()
                cpuUsage      = results["cpu"] ?: 0.0
                uptimeSeconds = (results["uptime"] ?: 0.0).toLong()
            }
        } catch (_: Exception) {
            metricsResponse { isOnline = false; serverName = "Tagomori" }
        }
    }

    private suspend fun queryVersion(): String = try {
        val res: String = http.get("$vmUrl/api/v1/query") {
            parameter("query", "minecraft_server_info")
        }.body()
        val json = Json.parseToJsonElement(res).jsonObject
        json["data"]?.jsonObject
            ?.get("result")?.jsonArray
            ?.firstOrNull()?.jsonObject
            ?.get("metric")?.jsonObject
            ?.get("version")?.jsonPrimitive?.content ?: "---"
    } catch (_: Exception) { "---" }

    private fun parseVmScalar(body: String): Double? = try {
        val json = Json.parseToJsonElement(body).jsonObject
        json["data"]?.jsonObject
            ?.get("result")?.jsonArray
            ?.firstOrNull()?.jsonObject
            ?.get("value")?.jsonArray
            ?.getOrNull(1)?.jsonPrimitive?.content
            ?.toDoubleOrNull()
    } catch (_: Exception) { null }
}
