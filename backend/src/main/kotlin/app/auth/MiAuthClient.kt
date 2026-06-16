package app.auth

import io.ktor.client.*
import io.ktor.client.call.body
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class MiAuthUser(
    val id: String,
    val username: String,
    val name: String? = null
)

@Serializable
data class MiAuthCheckResponse(
    val ok: Boolean,
    val token: String? = null,
    val user: MiAuthUser? = null
)

object MiAuthClient {
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                coerceInputValues = true
            })
        }
    }

    private const val TARGET_HOST = "sushi.ski"

    suspend fun checkSession(session: String): MiAuthUser? {
        try {
            val url = "https://$TARGET_HOST/api/miauth/$session/check"
            val response: MiAuthCheckResponse = client.post(url).body()
            
            if (response.ok && response.user != null) {
                // セキュリティ要件: token は保存もログ出力もせず即時破棄する
                return response.user
            }
        } catch (e: Exception) {
            System.err.println("MiAuth check failed: ${e.message}")
        }
        return null
    }
}
