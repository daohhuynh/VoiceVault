//
//  StorageServiceProtocol.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Service Contract: Persistence
//

import Foundation

// MARK: - StorageError

/// Errors that can occur during journal entry persistence operations.
enum StorageError: Error, LocalizedError, Sendable {

    /// The requested entry was not found in the data store.
    case entryNotFound(id: UUID)

    /// A SwiftData save or fetch operation failed.
    case persistenceFailure(underlying: String)

    /// The model container could not be initialized.
    case containerInitializationFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .entryNotFound(let id):
            return "Journal entry not found: \(id.uuidString)"
        case .persistenceFailure(let msg):
            return "Storage error: \(msg)"
        case .containerInitializationFailed(let msg):
            return "Failed to initialize data store: \(msg)"
        }
    }
}

// MARK: - SortOrder

/// Specifies the sort order for journal entry queries.
enum JournalSortOrder: Sendable {
    /// Most recent entries first.
    case newestFirst
    /// Oldest entries first.
    case oldestFirst
}

// MARK: - StorageServiceProtocol

/// Defines the contract for persisting and querying `JournalEntry` models.
///
/// **Owner:** Developer C (Storage Module)
///
/// ## Responsibilities
/// - Save new journal entries to the SwiftData store.
/// - Retrieve entries by ID, date range, or keyword search.
/// - Update existing entries (e.g., after NLP processing completes).
/// - Delete entries.
///
/// ## Implementation Notes
/// - The real implementation (`StorageService`) uses SwiftData's `ModelContext`
///   and `ModelContainer` directly.
/// - All operations MUST be performed on the appropriate `ModelActor` context
///   to ensure thread safety with SwiftData.
/// - The mock implementation (`MockStorageService`) stores entries in-memory
///   using a simple array for instant testing.
///
/// ## Usage
/// ```swift
/// let storage: StorageServiceProtocol = environment.storageService
/// try await storage.save(entry: newEntry)
/// let history = try await storage.fetchAll(sortedBy: .newestFirst)
/// ```
protocol StorageServiceProtocol: Sendable {

    /// Persists a new journal entry to the data store.
    ///
    /// If an entry with the same `id` already exists, it will be updated
    /// (upsert behavior).
    ///
    /// - Parameter entry: The `JournalEntry` to save.
    /// - Throws: `StorageError.persistenceFailure` if the save operation fails.
    func save(entry: JournalEntry) async throws

    /// Retrieves a single journal entry by its unique identifier.
    ///
    /// - Parameter id: The UUID of the entry to fetch.
    /// - Returns: The matching `JournalEntry`.
    /// - Throws: `StorageError.entryNotFound` if no entry matches the given ID.
    func fetch(byId id: UUID) async throws -> JournalEntry

    /// Retrieves all journal entries, sorted by the specified order.
    ///
    /// - Parameter sortedBy: The desired sort order. Defaults to `.newestFirst`.
    /// - Returns: An array of all `JournalEntry` models in the store.
    /// - Throws: `StorageError.persistenceFailure` if the fetch operation fails.
    func fetchAll(sortedBy: JournalSortOrder) async throws -> [JournalEntry]

    /// Retrieves journal entries within a specific date range.
    ///
    /// Both bounds are inclusive.
    ///
    /// - Parameters:
    ///   - startDate: The beginning of the date range.
    ///   - endDate: The end of the date range.
    /// - Returns: An array of matching `JournalEntry` models, newest first.
    /// - Throws: `StorageError.persistenceFailure` if the fetch operation fails.
    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [JournalEntry]

    /// Searches for entries whose transcript contains the given query string.
    ///
    /// The search is case-insensitive and matches partial strings.
    ///
    /// - Parameter query: The text to search for in transcripts.
    /// - Returns: An array of matching `JournalEntry` models.
    /// - Throws: `StorageError.persistenceFailure` if the search operation fails.
    func searchEntries(matching query: String) async throws -> [JournalEntry]

    /// Deletes a journal entry by its unique identifier.
    ///
    /// - Parameter id: The UUID of the entry to delete.
    /// - Throws: `StorageError.entryNotFound` if no entry matches the given ID.
    func delete(byId id: UUID) async throws

    /// Returns the total count of journal entries in the store.
    ///
    /// - Returns: The number of persisted entries.
    /// - Throws: `StorageError.persistenceFailure` if the count operation fails.
    func entryCount() async throws -> Int
}
