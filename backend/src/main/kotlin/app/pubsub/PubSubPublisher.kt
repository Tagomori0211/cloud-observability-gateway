package app.pubsub

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.*
import java.time.Instant
import java.util.Base64

/**
 * GCE の Application Default Credentials（メタデータサーバー経由）で
 * アクセストークンを取得し、Pub/Sub REST API へメッセージを publish する。
 *
 * 環境変数 PUBSUB_TOPIC: projects/{project}/topics/{topic} 形式で指定。
 * 未設定時は publish を無音でスキップする。
 */
object PubSubPublisher {
    private val topic = System.getenv("PUBSUB_TOPIC") ?: ""

    private val http = HttpClient(CIO) {
        install(ContentNegotiation) { json() }
        expectSuccess = false
    }

    // トークンキャッシュ（有効期限 - 60 秒前に再取得）
    @Volatile private var cachedToken: String? = null
    @Volatile private var tokenExpiryEpoch: Long = 0L

    private suspend fun accessToken(): String? {
        val now = System.currentTimeMillis() / 1000
        cachedToken?.let { if (now < tokenExpiryEpoch - 60) return it }

        return try {
            val body: String = http.get(
                "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
            ) {
                header("Metadata-Flavor", "Google")
            }.body()

            val json = Json.parseToJsonElement(body).jsonObject
            val token = json["access_token"]?.jsonPrimitive?.content ?: return null
            val expiresIn = json["expires_in"]?.jsonPrimitive?.longOrNull ?: 3600L
            cachedToken = token
            tokenExpiryEpoch = now + expiresIn
            token
        } catch (_: Exception) {
            null
        }
    }

    /**
     * @param server "survival" | "bedrock" | "all"
     * @return publish 成功なら true（PUBSUB_TOPIC 未設定や GCE 外では false）
     */
    suspend fun publish(server: String): Boolean {
        if (topic.isBlank()) return false
        val token = accessToken() ?: return false

        val payload = buildJsonObject {
            put("command",     "list")
            put("server",      server)
            put("source",      "tagomori-dashboard")
            put("triggeredAt", Instant.now().toString())
        }
        val dataB64 = Base64.getEncoder()
            .encodeToString(payload.toString().toByteArray(Charsets.UTF_8))

        val body = buildJsonObject {
            put("messages", buildJsonArray {
                add(buildJsonObject { put("data", dataB64) })
            })
        }.toString()

        val res = http.post("https://pubsub.googleapis.com/v1/$topic:publish") {
            header(HttpHeaders.Authorization, "Bearer $token")
            contentType(ContentType.Application.Json)
            setBody(body)
        }
        return res.status.isSuccess()
    }
}
