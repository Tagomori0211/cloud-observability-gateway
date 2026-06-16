package app.auth

import org.mindrot.jbcrypt.BCrypt

object PasswordHasher {
    fun hash(password: String): String = BCrypt.hashpw(password, BCrypt.gensalt())

    fun verify(password: String, hash: String): Boolean =
        try {
            BCrypt.checkpw(password, hash)
        } catch (e: Exception) {
            false
        }
}
