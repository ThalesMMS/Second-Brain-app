import Foundation
import SQLite3
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

/// Populates the given persistence controller with `count` generated manual notes.
/// - Parameters:
///   - persistence: The persistence controller whose repository will receive the created notes.
///   - count: The number of notes to create. Notes are created for indices `0` through `count - 1`.
///   - prefix: The title prefix for each note; each title is formed as `"\(prefix) \(index)"`.
/// - Throws: Any error produced by the persistence repository while creating a note.
@MainActor
func populateLargeCorpus(
    in persistence: PersistenceController,
    count: Int,
    prefix: String = "Archive note"
) async throws {
    for index in 0..<count {
        _ = try await persistence.repository.createNote(
            title: "\(prefix) \(index)",
            body: "Routine archive entry \(index). Unrelated planning, groceries, and logistics.",
            source: .manual,
            initialEntryKind: .creation
        )
    }
}

/// Returns the number of rows in the named SQLite table at the provided store URL.
/// - Parameters:
///   - storeURL: Filesystem URL of the SQLite database file.
///   - table: The name of the table to count rows for; if the table does not exist the function returns `0`.
/// - Returns: The row count for the specified table. Returns `0` when the table is not present.
/// - Throws: `SQLiteStoreInspectionError.openFailed(path:)` if the database cannot be opened; `SQLiteStoreInspectionError.prepareFailed(query:)` if preparing a statement fails; `SQLiteStoreInspectionError.stepFailed(query:)` if stepping the statement fails.
func countRows(inSQLiteStoreAt storeURL: URL, table: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open(storeURL.path, &database) == SQLITE_OK else {
        defer { sqlite3_close(database) }
        throw SQLiteStoreInspectionError.openFailed(path: storeURL.path)
    }
    defer { sqlite3_close(database) }

    let tableExistsQuery = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(table)';"
    var tableStatement: OpaquePointer?
    guard sqlite3_prepare_v2(database, tableExistsQuery, -1, &tableStatement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(tableStatement) }
        throw SQLiteStoreInspectionError.prepareFailed(query: tableExistsQuery)
    }
    defer { sqlite3_finalize(tableStatement) }

    guard sqlite3_step(tableStatement) == SQLITE_ROW else {
        throw SQLiteStoreInspectionError.stepFailed(query: tableExistsQuery)
    }

    guard sqlite3_column_int(tableStatement, 0) > 0 else {
        return 0
    }

    let rowCountQuery = "SELECT COUNT(*) FROM \(table);"
    var rowStatement: OpaquePointer?
    guard sqlite3_prepare_v2(database, rowCountQuery, -1, &rowStatement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(rowStatement) }
        throw SQLiteStoreInspectionError.prepareFailed(query: rowCountQuery)
    }
    defer { sqlite3_finalize(rowStatement) }

    guard sqlite3_step(rowStatement) == SQLITE_ROW else {
        throw SQLiteStoreInspectionError.stepFailed(query: rowCountQuery)
    }

    return Int(sqlite3_column_int(rowStatement, 0))
}

/// Checks whether a column with the given name exists in a table within the SQLite store at the provided URL.
/// - Parameters:
///   - storeURL: File URL of the SQLite database.
///   - table: Name of the table to inspect.
///   - column: Name of the column to check for existence.
/// - Returns: `true` if the named column exists in the specified table, `false` otherwise.
/// - Throws: `SQLiteStoreInspectionError.openFailed(path:)` if the database cannot be opened; `SQLiteStoreInspectionError.prepareFailed(query:)` if preparing the inspection query fails; `SQLiteStoreInspectionError.stepFailed(query:)` if executing the prepared statement fails.
func columnExists(inSQLiteStoreAt storeURL: URL, table: String, column: String) throws -> Bool {
    var database: OpaquePointer?
    guard sqlite3_open(storeURL.path, &database) == SQLITE_OK else {
        defer { sqlite3_close(database) }
        throw SQLiteStoreInspectionError.openFailed(path: storeURL.path)
    }
    defer { sqlite3_close(database) }

    let query = "SELECT COUNT(*) FROM pragma_table_info('\(table)') WHERE name = '\(column)';"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(statement) }
        throw SQLiteStoreInspectionError.prepareFailed(query: query)
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SQLiteStoreInspectionError.stepFailed(query: query)
    }

    return sqlite3_column_int(statement, 0) > 0
}

enum SQLiteStoreInspectionError: LocalizedError {
    case openFailed(path: String)
    case prepareFailed(query: String)
    case stepFailed(query: String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(path):
            "Failed to open SQLite store at \(path)."
        case let .prepareFailed(query):
            "Failed to prepare SQLite query: \(query)"
        case let .stepFailed(query):
            "Failed to execute SQLite query: \(query)"
        }
    }
}