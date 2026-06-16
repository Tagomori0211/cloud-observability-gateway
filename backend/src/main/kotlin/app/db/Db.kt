package app.db

import java.sql.Connection

inline fun <R> withConnection(block: (Connection) -> R): R {
    return Database.getConnection().use(block)
}

inline fun <R> runInTransaction(block: (Connection) -> R): R {
    return Database.getConnection().use { conn ->
        val oldAutoCommit = conn.autoCommit
        conn.autoCommit = false
        try {
            val result = block(conn)
            conn.commit()
            result
        } catch (e: Exception) {
            conn.rollback()
            throw e
        } finally {
            conn.autoCommit = oldAutoCommit
        }
    }
}
