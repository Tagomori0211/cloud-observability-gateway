package app.db

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import org.flywaydb.core.Flyway
import java.sql.Connection

object Database {
    private var dataSource: HikariDataSource? = null

    fun init() {
        val url = System.getenv("DB_URL") ?: "jdbc:mariadb://localhost:3306/tagomori_status"
        val user = System.getenv("DB_USER") ?: "app"
        val password = System.getenv("DB_PASSWORD") ?: ""

        val config = HikariConfig().apply {
            jdbcUrl = url
            username = user
            this.password = password
            driverClassName = "org.mariadb.jdbc.Driver"
            maximumPoolSize = 10
            isAutoCommit = true
        }

        val ds = HikariDataSource(config)
        dataSource = ds

        // Flyway migration
        Flyway.configure()
            .dataSource(ds)
            .cleanDisabled(true)
            .load()
            .migrate()
    }

    fun getConnection(): Connection {
        return dataSource?.connection ?: throw IllegalStateException("Database not initialized")
    }
}
