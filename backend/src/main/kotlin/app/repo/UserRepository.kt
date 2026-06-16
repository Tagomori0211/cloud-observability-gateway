package app.repo

import app.db.withConnection
import java.sql.ResultSet
import java.sql.Statement

data class DbUser(
    val id: Long,
    val misskeyId: String,
    val misskeyHost: String,
    val username: String
)

object UserRepository {
    fun upsert(misskeyId: String, misskeyHost: String, username: String): DbUser {
        return withConnection { conn ->
            val sql = """
                INSERT INTO users (misskey_id, misskey_host, username) 
                VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE username = VALUES(username)
            """.trimIndent()

            conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS).use { stmt ->
                stmt.setString(1, misskeyId)
                stmt.setString(2, misskeyHost)
                stmt.setString(3, username)
                stmt.executeUpdate()

                stmt.generatedKeys.use { rs ->
                    if (rs.next()) {
                        val generatedId = rs.getLong(1)
                        if (generatedId > 0) {
                            return@withConnection DbUser(generatedId, misskeyId, misskeyHost, username)
                        }
                    }
                }
            }

            findByMisskey(misskeyId, misskeyHost) ?: throw IllegalStateException("Failed to retrieve upserted user")
        }
    }

    fun findById(id: Long): DbUser? {
        return withConnection { conn ->
            val sql = "SELECT id, misskey_id, misskey_host, username FROM users WHERE id = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setLong(1, id)
                stmt.executeQuery().use { rs ->
                    if (rs.next()) {
                        return@withConnection mapRow(rs)
                    }
                }
            }
            null
        }
    }

    fun findByMisskey(misskeyId: String, misskeyHost: String): DbUser? {
        return withConnection { conn ->
            val sql = "SELECT id, misskey_id, misskey_host, username FROM users WHERE misskey_id = ? AND misskey_host = ?"
            conn.prepareStatement(sql).use { stmt ->
                stmt.setString(1, misskeyId)
                stmt.setString(2, misskeyHost)
                stmt.executeQuery().use { rs ->
                    if (rs.next()) {
                        return@withConnection mapRow(rs)
                    }
                }
            }
            null
        }
    }

    private fun mapRow(rs: ResultSet): DbUser {
        return DbUser(
            id = rs.getLong("id"),
            misskeyId = rs.getString("misskey_id"),
            misskeyHost = rs.getString("misskey_host"),
            username = rs.getString("username")
        )
    }
}
