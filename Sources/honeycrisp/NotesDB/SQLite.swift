import Foundation
import SQLite3

final class SQLiteDB {
    private var handle: OpaquePointer?

    init(path: String, readonly: Bool = true) throws {
        var db: OpaquePointer?
        let flags = readonly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let result = sqlite3_open_v2(path, &db, flags, nil)
        if result != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw CLIError(message: "Failed to open database: \(message)")
        }
        handle = db
    }

    deinit {
        close()
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func tableColumns(_ table: String) throws -> Set<String> {
        let rows = try query("PRAGMA table_info(\(table))")
        var columns: Set<String> = []
        for row in rows {
            if let name = row.string("NAME") {
                columns.insert(name.uppercased())
            }
        }
        return columns
    }

    func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        guard let handle else {
            throw CLIError(message: "Database not open")
        }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw CLIError(message: "Failed to prepare query")
        }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            try bind(value, to: stmt, at: position)
        }

        var rows: [SQLiteRow] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                rows.append(SQLiteRow(statement: stmt))
            } else if step == SQLITE_DONE {
                break
            } else {
                throw CLIError(message: "Failed to execute query")
            }
        }
        return rows
    }

    func queryOne(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> SQLiteRow? {
        let rows = try query(sql, bindings)
        return rows.first
    }

    private func bind(_ value: SQLiteValue, to stmt: OpaquePointer?, at index: Int32) throws {
        let result: Int32
        switch value {
        case .null:
            result = sqlite3_bind_null(stmt, index)
        case .integer(let int):
            result = sqlite3_bind_int64(stmt, index, int)
        case .real(let double):
            result = sqlite3_bind_double(stmt, index, double)
        case .text(let text):
            result = text.withCString { cString in
                sqlite3_bind_text(stmt, index, cString, -1, sqliteTransient)
            }
        case .blob(let data):
            result = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(stmt, index, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
            }
        }
        if result != SQLITE_OK {
            throw CLIError(message: "Failed to bind query parameter")
        }
    }
}

enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

struct SQLiteRow {
    let values: [String: SQLiteValue]

    init(statement stmt: OpaquePointer?) {
        var row: [String: SQLiteValue] = [:]
        let columnCount = sqlite3_column_count(stmt)
        for index in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(stmt, index)).uppercased()
            let type = sqlite3_column_type(stmt, index)
            switch type {
            case SQLITE_INTEGER:
                row[name] = .integer(sqlite3_column_int64(stmt, index))
            case SQLITE_FLOAT:
                row[name] = .real(sqlite3_column_double(stmt, index))
            case SQLITE_TEXT:
                if let cString = sqlite3_column_text(stmt, index) {
                    row[name] = .text(String(cString: cString))
                } else {
                    row[name] = .null
                }
            case SQLITE_BLOB:
                let bytes = sqlite3_column_blob(stmt, index)
                let length = Int(sqlite3_column_bytes(stmt, index))
                if let bytes {
                    row[name] = .blob(Data(bytes: bytes, count: length))
                } else {
                    row[name] = .null
                }
            default:
                row[name] = .null
            }
        }
        values = row
    }

    func string(_ key: String) -> String? {
        switch values[key.uppercased()] {
        case .text(let text): return text
        case .integer(let int): return String(int)
        case .real(let real): return String(real)
        default: return nil
        }
    }

    func int64(_ key: String) -> Int64? {
        switch values[key.uppercased()] {
        case .integer(let int): return int
        case .real(let real): return Int64(real)
        case .text(let text): return Int64(text)
        default: return nil
        }
    }

    func double(_ key: String) -> Double? {
        switch values[key.uppercased()] {
        case .real(let real): return real
        case .integer(let int): return Double(int)
        case .text(let text): return Double(text)
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool? {
        guard let value = int64(key) else { return nil }
        return value != 0
    }

    func data(_ key: String) -> Data? {
        switch values[key.uppercased()] {
        case .blob(let data): return data
        default: return nil
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
