package app.routes

import app.auth.MiAuthClient
import app.auth.PasswordHasher
import app.auth.SessionAuth
import app.pubsub.PubSubPublisher
import app.repo.DbUser
import app.repo.SessionRepository
import app.repo.UserRepository
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import java.time.Instant

@Serializable
data class CompleteRequest(
    val session: String
)

@Serializable
data class RegisterResponse(
    val username: String,
    val needPassword: Boolean
)

@Serializable
data class SetPasswordRequest(
    val username: String,
    val password: String
)

@Serializable
data class LoginRequest(
    val username: String,
    val password: String
)

@Serializable
data class UserResponse(
    val id: Long,
    val misskeyId: String,
    val misskeyHost: String,
    val username: String
)

private val USERNAME_REGEX = Regex("^[A-Za-z0-9_]{1,32}$")
private const val MIN_PASSWORD_LENGTH = 8

private fun startSession(call: ApplicationCall, user: DbUser) {
    val token = SessionAuth.generateToken()
    val tokenHash = SessionAuth.hashToken(token)
    val expiresAt = Instant.now().plusSeconds(SessionAuth.SESSION_DURATION_SECONDS)
    SessionRepository.create(tokenHash, user.id, expiresAt)
    SessionAuth.setSessionCookie(call, token)
}

fun Route.authRoutes() {
    route("/auth") {
        // MiAuth は初回登録の本人確認専用。ログインには使わない（ID/PASS のみ）。
        post("/miauth/register") {
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

            if (user.passwordHash != null) {
                call.respond(HttpStatusCode.Conflict, mapOf("error" to "already_registered"))
                return@post
            }

            call.respond(HttpStatusCode.OK, RegisterResponse(username = user.username, needPassword = true))
        }

        post("/register/set-password") {
            val req = try {
                call.receive<SetPasswordRequest>()
            } catch (e: Exception) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid request body"))
                return@post
            }

            if (req.password.length < MIN_PASSWORD_LENGTH) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Password must be at least $MIN_PASSWORD_LENGTH characters"))
                return@post
            }

            val user = UserRepository.findByUsername(req.username)
            if (user == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "User not found"))
                return@post
            }
            if (user.passwordHash != null) {
                call.respond(HttpStatusCode.Conflict, mapOf("error" to "Password already set"))
                return@post
            }

            UserRepository.setPassword(user.id, PasswordHasher.hash(req.password))
            startSession(call, user)

            call.respond(HttpStatusCode.OK, UserResponse(
                id = user.id,
                misskeyId = user.misskeyId,
                misskeyHost = user.misskeyHost,
                username = user.username
            ))
        }

        post("/login") {
            val req = try {
                call.receive<LoginRequest>()
            } catch (e: Exception) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid request body"))
                return@post
            }

            if (!USERNAME_REGEX.matches(req.username)) {
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Invalid credentials"))
                return@post
            }

            val user = UserRepository.findByUsername(req.username)
            if (user == null || user.passwordHash == null || !PasswordHasher.verify(req.password, user.passwordHash)) {
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Invalid credentials"))
                return@post
            }

            startSession(call, user)

            // ログイン時に /list コマンドをトリガー（サーバーコンソールにプレイヤー一覧を出力）
            call.application.launch { PubSubPublisher.publish("all") }

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
