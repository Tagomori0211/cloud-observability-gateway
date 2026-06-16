package app.auth

import app.repo.DbUser
import app.repo.SessionRepository
import app.repo.UserRepository
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.util.*
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.util.*

object SessionAuth {
    private val secureRandom = SecureRandom()
    val userKey = AttributeKey<DbUser>("AuthenticatedUser")

    const val COOKIE_NAME = "sid"
    const val SESSION_DURATION_SECONDS = 2592000L // 30日

    fun generateToken(): String {
        val bytes = ByteArray(32)
        secureRandom.nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    fun hashToken(token: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(token.toByteArray())
        return hash.joinToString("") { "%02x".format(it) }
    }

    fun intercept(context: PipelineContext<Unit, ApplicationCall>) {
        val call = context.call
        val token = call.request.cookies[COOKIE_NAME]
        if (token == null) {
            context.finish()
            return
        }

        val tokenHash = hashToken(token)
        val session = SessionRepository.findByTokenHash(tokenHash)
        if (session == null || session.expiresAt.isBefore(Instant.now())) {
            if (session != null) {
                SessionRepository.deleteByTokenHash(tokenHash)
            }
            clearSessionCookie(call)
            context.finish()
            return
        }

        val user = UserRepository.findById(session.userId)
        if (user == null) {
            context.finish()
            return
        }

        call.attributes.put(userKey, user)
    }

    fun setSessionCookie(call: ApplicationCall, token: String) {
        call.response.cookies.append(
            name = COOKIE_NAME,
            value = token,
            path = "/",
            maxAge = SESSION_DURATION_SECONDS.toInt(),
            httpOnly = true,
            secure = true,
            extensions = mapOf("SameSite" to "Lax")
        )
    }

    fun clearSessionCookie(call: ApplicationCall) {
        call.response.cookies.append(
            name = COOKIE_NAME,
            value = "",
            path = "/",
            maxAge = 0,
            httpOnly = true,
            secure = true,
            extensions = mapOf("SameSite" to "Lax")
        )
    }

    val ApplicationCall.authenticatedUser: DbUser
        get() = attributes.getOrNull(userKey) ?: throw IllegalStateException("User not authenticated in this call")
}
