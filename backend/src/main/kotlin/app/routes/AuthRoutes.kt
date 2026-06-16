package app.routes

import app.auth.MiAuthClient
import app.auth.SessionAuth
import app.repo.SessionRepository
import app.repo.UserRepository
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import java.time.Instant

@Serializable
data class CompleteRequest(
    val session: String
)

@Serializable
data class UserResponse(
    val id: Long,
    val misskeyId: String,
    val misskeyHost: String,
    val username: String
)

fun Route.authRoutes() {
    route("/auth") {
        post("/miauth/complete") {
            val req = try {
                call.receive<CompleteRequest>()
            } catch (e: Exception) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid request body"))
                return@post
            }

            if (req.session.isBlank()) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Session UUID is required"))
                return@post
            }

            val miUser = MiAuthClient.checkSession(req.session)
            if (miUser == null) {
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "MiAuth verification failed"))
                return@post
            }

            val user = UserRepository.upsert(
                misskeyId = miUser.id,
                misskeyHost = "sushi.ski",
                username = miUser.username
            )

            val token = SessionAuth.generateToken()
            val tokenHash = SessionAuth.hashToken(token)
            val expiresAt = Instant.now().plusSeconds(SessionAuth.SESSION_DURATION_SECONDS)
            SessionRepository.create(tokenHash, user.id, expiresAt)

            SessionAuth.setSessionCookie(call, token)

            call.respond(HttpStatusCode.OK, UserResponse(
                id = user.id,
                misskeyId = user.misskeyId,
                misskeyHost = user.misskeyHost,
                username = user.username
            ))
        }
    }

    post("/logout") {
        val token = call.request.cookies[SessionAuth.COOKIE_NAME]
        if (token != null) {
            val tokenHash = SessionAuth.hashToken(token)
            SessionRepository.deleteByTokenHash(tokenHash)
        }

        SessionAuth.clearSessionCookie(call)
        call.respond(HttpStatusCode.NoContent)
    }
}
