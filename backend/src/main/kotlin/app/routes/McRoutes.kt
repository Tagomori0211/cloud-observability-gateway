package app.routes

import app.pubsub.PubSubPublisher
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

@Serializable
private data class ListTriggerRequest(val server: String = "all")

private val VALID_SERVERS = setOf("survival", "bedrock", "all")

fun Route.mcRoutes() {
    route("/mc") {
        // 認証不要: /list は読み取り専用コマンド
        post("/list-trigger") {
            val req = try {
                call.receive<ListTriggerRequest>()
            } catch (_: Exception) {
                ListTriggerRequest()
            }
            val server = if (req.server in VALID_SERVERS) req.server else "all"
            PubSubPublisher.publish(server)  // 失敗しても 204 を返す
            call.respond(HttpStatusCode.NoContent)
        }
    }
}
