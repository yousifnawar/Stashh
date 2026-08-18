import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBError: Error, CustomStringConvertible {
    case open(String), prepare(String), step(String)
    var description: String {
        switch self {
        case .open(let m): return "sqlite open: \(m)"
        case .prepare(let m): return "sqlite prepare: \(m)"
        case .step(let m): return "sqlite step: \(m)"
        }
    }
}

/// Minimal synchronous SQLite wrapper. All access is funnelled through ClipStore's
/// serial queue, so no additional locking is needed here.
final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &h, flags, nil) == SQLITE_OK, let h else {
            throw DBError.open(String(cString: sqlite3_errmsg(h)))
        }
        handle = h
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA foreign_keys=ON;")
    }

    deinit { if let handle { sqlite3_close_v2(handle) } }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw DBError.step(msg)
        }
    }

    @discardableResult
    func run(_ sql: String, _ params: [Value] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare("\(errorMessage) — \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError.step(errorMessage) }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ params: [Value] = []) throws -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare("\(errorMessage) — \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)

        let columnCount = Int(sqlite3_column_count(stmt))
        var names: [String] = []
        for i in 0..<columnCount { names.append(String(cString: sqlite3_column_name(stmt, Int32(i)))) }

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var dict: [String: Value] = [:]
            for i in 0..<columnCount {
                let idx = Int32(i)
                switch sqlite3_column_type(stmt, idx) {
                case SQLITE_INTEGER: dict[names[i]] = .int(Int(sqlite3_column_int64(stmt, idx)))
                case SQLITE_FLOAT:   dict[names[i]] = .double(sqlite3_column_double(stmt, idx))
                case SQLITE_NULL:    dict[names[i]] = .null
                default:
                    if let cs = sqlite3_column_text(stmt, idx) {
                        dict[names[i]] = .text(String(cString: cs))
                    } else { dict[names[i]] = .null }
                }
            }
            rows.append(Row(values: dict))
        }
        return rows
    }

    private func bind(_ stmt: OpaquePointer?, _ params: [Value]) {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, Int64(v))
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            }
        }
    }

    // MARK: Types

    enum Value {
        case null, int(Int), double(Double), text(String)

        static func opt(_ s: String?) -> Value { s.map { .text($0) } ?? .null }
        static func date(_ d: Date?) -> Value { d.map { .double($0.timeIntervalSince1970) } ?? .null }
        static func bool(_ b: Bool) -> Value { .int(b ? 1 : 0) }
    }

    struct Row {
        let values: [String: Value]

        func string(_ k: String) -> String? {
            if case .text(let v)? = values[k] { return v }
            return nil
        }
        func int(_ k: String) -> Int {
            switch values[k] {
            case .int(let v)?: return v
            case .double(let v)?: return Int(v)
            case .text(let v)?: return Int(v) ?? 0
            default: return 0
            }
        }
        func double(_ k: String) -> Double? {
            switch values[k] {
            case .double(let v)?: return v
            case .int(let v)?: return Double(v)
            default: return nil
            }
        }
        func bool(_ k: String) -> Bool { int(k) != 0 }
        func date(_ k: String) -> Date? { double(k).map { Date(timeIntervalSince1970: $0) } }
    }
}
