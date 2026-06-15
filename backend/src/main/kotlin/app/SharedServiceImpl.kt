package app

import app.generated.GetMetricsRequest
import app.generated.MetricsResponse
import app.generated.MetricsServiceGrpcKt
import app.generated.ServerType
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
        fetchFromVictoriaMetrics(request.server)

    // Server sends a snapshot every 15 seconds to keep the Cloudflare Tunnel
    // connection alive (idle timeout ≈ 100s).
    override fun streamMetrics(request: GetMetricsRequest): Flow<MetricsResponse> = flow {
        while (true) {
            emit(fetchFromVictoriaMetrics(request.server))
            delay(15_000)
        }
    }

    private suspend fun fetchFromVictoriaMetrics(server: ServerType): MetricsResponse {
        // mc-monitor job ラベルとコンテナ名をサーバー種別で分岐する。
        // CPU limit: Java = 4000m (4 コア) / Bedrock = 8000m (8 コア) — query.txt 準拠。
        val isBedrock  = server == ServerType.BEDROCK
        val job        = if (isBedrock) "bedrock"  else "survival"
        val container  = if (isBedrock) "bedrock"  else "minecraft"
        val cpuLimit   = if (isBedrock) 8          else 4
        val serverName = if (isBedrock) "Bedrock"  else "Java"

        return try {
            // mc-monitor が報告するオンライン状態で判定する
            val healthy = vmQuery("""minecraft_status_healthy{job="$job"}""")
            if (healthy != 1.0) {
                return metricsResponse { isOnline = false; this.serverName = serverName }
            }

            metricsResponse {
                isOnline      = true
                this.serverName = serverName
                version       = queryVersion(job)
                latencyMs     = vmQuery("""minecraft_status_latency_ms{job="$job"}""") ?: 0.0
                playersOnline = (vmQuery("""minecraft_status_player_count{job="$job"}""") ?: 0.0).toInt()
                playersMax    = (vmQuery("""minecraft_status_player_max{job="$job"}""")  ?: 0.0).toInt()
                val memUsed   = vmQuery("""container_memory_working_set_bytes{namespace="minecraft",container="$container"}""")  ?: 0.0
                val memMax    = vmQuery("""container_spec_memory_limit_bytes{namespace="minecraft",container="$container"}""")   ?: 0.0
                memoryUsedMb  = (memUsed / 1_048_576).toInt()
                memoryMaxMb   = (memMax  / 1_048_576).toInt()
                cpuUsage      = vmQuery(
                    """rate(container_cpu_usage_seconds_total{namespace="minecraft",container="$container"}[5m]) / $cpuLimit * 100"""
                ) ?: 0.0
                uptimeSeconds = 0L
            }
        } catch (_: Exception) {
            metricsResponse { isOnline = false; this.serverName = serverName }
        }
    }

    private suspend fun vmQuery(query: String): Double? {
        val body: String = http.get("$vmUrl/api/v1/query") {
            parameter("query", query)
        }.body()
        return parseVmScalar(body)
    }

    private suspend fun queryVersion(job: String): String = try {
        val body: String = http.get("$vmUrl/api/v1/query") {
            parameter("query", """minecraft_status_healthy{job="$job"}""")
        }.body()
        Json.parseToJsonElement(body).jsonObject["data"]?.jsonObject
            ?.get("result")?.jsonArray
            ?.firstOrNull()?.jsonObject
            ?.get("metric")?.jsonObject
            ?.get("version")?.jsonPrimitive?.content ?: "---"
    } catch (_: Exception) { "---" }

    private fun parseVmScalar(body: String): Double? = try {
        Json.parseToJsonElement(body).jsonObject["data"]?.jsonObject
            ?.get("result")?.jsonArray
            ?.firstOrNull()?.jsonObject
            ?.get("value")?.jsonArray
            ?.getOrNull(1)?.jsonPrimitive?.content
            ?.toDoubleOrNull()
    } catch (_: Exception) { null }
}
