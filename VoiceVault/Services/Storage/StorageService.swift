//
//  StorageService.swift
//  VoiceVault
//
//  Owner: Dev 2 — Local Intelligence Pipeline (The "Brain")
//  Hackathon Day 1 — Production Persistence Layer
//
//  Provides SwiftData-backed persistence for JournalEntry models.
//  All CRUD operations are performed via the injected ModelContext.
//  Includes a semantic similarity search (vector RAG) that ranks
//  stored entries by cosine distance to a query embedding.
//

import Foundation
import Observation
import os
import SwiftData

// MARK: - StorageService

/// Production implementation of `StorageServiceProtocol`.
///
/// Uses Apple's `SwiftData` framework to persist `JournalEntry` models
/// on-device. The `ModelContext` is injected at initialization time so the
/// service never owns the `ModelContainer` lifecycle — that responsibility
/// stays with the `@main` App struct.
///
/// ## Architecture
/// The service wraps every SwiftData operation in a `@MainActor.run` block
/// because `ModelContext` is not `Sendable` and must be accessed from the
/// actor that owns it (the main actor, since the container is provided by
/// the SwiftUI scene). This is the standard SwiftData pattern for iOS 17.
///
/// ## Semantic Search (RAG)
/// `findSimilarEntries(to:topK:)` performs in-memory cosine similarity
/// ranking across all stored entries' vector embeddings. This is efficient
/// for the expected hackathon-scale dataset (hundreds of entries). For
/// production-scale datasets (10k+), consider migrating to an on-device
/// vector index.
///
/// ## Error Handling
/// All SwiftData failures are caught and re-thrown as typed `StorageError`
/// cases with the underlying error message preserved for diagnostics.
@Observable
final class StorageService: StorageServiceProtocol, @unchecked Sendable {

    // MARK: - Dependencies

    /// The SwiftData model context used for all persistence operations.
    /// Must be accessed on the main actor since it was created from the
    /// scene's `ModelContainer`.
    @ObservationIgnored
    private let modelContext: ModelContext

    /// Logger scoped to the storage subsystem for structured diagnostics.
    @ObservationIgnored
    private let logger = Logger(subsystem: "com.voicevault.app", category: "storage")

    // MARK: - Initializer

    /// Creates a new `StorageService` backed by the given `ModelContext`.
    ///
    /// The caller is responsible for providing a context derived from the
    /// app's `ModelContainer` (typically via `container.mainContext`).
    ///
    /// - Parameter modelContext: The SwiftData context to use for all CRUD operations.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        logger.info("💾 StorageService initialized with ModelContext")
    }

    // MARK: - Protocol Conformance: Save

    /// Persists a new journal entry to the SwiftData store.
    ///
    /// If an entry with the same `id` already exists, its fields are updated
    /// in place (upsert behavior). Otherwise, the entry is inserted as new.
    ///
    /// - Parameter entry: The `JournalEntry` to save.
    /// - Throws: `StorageError.persistenceFailure` if the save operation fails.
    func save(entry: JournalEntry) async throws {
        logger.info("💾 save(entry:) — id: \(entry.id.uuidString)")

        do {
            try await MainActor.run {
                // Check if the entry already exists (upsert)
                let targetId = entry.id
                var descriptor = FetchDescriptor<JournalEntry>(
                    predicate: #Predicate<JournalEntry> { $0.id == targetId }
                )
                descriptor.fetchLimit = 1

                let existing = try modelContext.fetch(descriptor)

                if let existingEntry = existing.first {
                    // Update existing entry in place
                    existingEntry.rawTranscript = entry.rawTranscript
                    existingEntry.sentimentScore = entry.sentimentScore
                    existingEntry.extractedKeywords = entry.extractedKeywords
                    existingEntry.vectorEmbedding = entry.vectorEmbedding
                    existingEntry.audioDurationSeconds = entry.audioDurationSeconds
                    existingEntry.audioReferenceKey = entry.audioReferenceKey
                    existingEntry.isFullyProcessed = entry.isFullyProcessed
                    existingEntry.timestamp = entry.timestamp
                    logger.debug("📝 Updated existing entry: \(targetId.uuidString)")
                } else {
                    // Insert new entry
                    modelContext.insert(entry)
                    logger.debug("➕ Inserted new entry: \(targetId.uuidString)")
                }

                try modelContext.save()
            }
            logger.info("✅ Entry saved successfully — id: \(entry.id.uuidString)")
        } catch let error as StorageError {
            throw error
        } catch {
            logger.error("❌ Save failed: \(error.localizedDescription)")
            throw StorageError.persistenceFailure(underlying: error.localizedDescription)
        }
    }

    // MARK: - Protocol Conformance: Fetch by ID

    /// Retrieves a single journal entry by its unique identifier.
    ///
    /// - Parameter id: The UUID of the entry to fetch.
    /// - Returns: The matching `JournalEntry`.
    /// - Throws: `StorageError.entryNotFound` if no entry matches the given ID.
    func fetch(byId id: UUID) async throws -> JournalEntry {
        logger.info("🔍 fetch(byId:) — id: \(id.uuidString)")

        do {
            let entry: JournalEntry? = try await MainActor.run {
                var descriptor = FetchDescriptor<JournalEntry>(
                    predicate: #Predicate<JournalEntry> { $0.id == id }
                )
                descriptor.fetchLimit = 1
                return try modelContext.fetch(descriptor).first
            }

            guard let entry else {
                logger.error("❌ Entry not found: \(id.uuidString)")
                throw StorageError.entryNotFound(id: id)
            }

            logger.debug("✅ Found entry: \(id.uuidString)")
            return entry
        } catch let error as StorageError {
            throw error
        } catch {
            logger.error("❌ Fetch failed: \(error.localizedDescription)")
            throw StorageError.persistenceFailure(underlying: error.localizedDescription)
        }
    }

    // MARK: - Protocol Conformance: Fetch All

    /// Retrieves all journal entries, sorted by the specified order.
    ///
    /// - Parameter sortedBy: The desired sort order. Defaults to `.newestFirst`.
    /// - Returns: An array of all `JournalEntry` models in the store.
    /// - Throws: `StorageError.persistenceFailure` if the fetch operation fails.
    func fetchAll(sortedBy: JournalSortOrder = .newestFirst) async throws -> [JournalEntry] {
        logger.info("📋 fetchAll(sortedBy: \(String(describing: sortedBy)))")

        do {
            let entries: [JournalEntry] = try await MainActor.run {
                let sortOrder: SortDescriptor<JournalEntry> = switch sortedBy {
                case .newestFirst:
                    SortDescriptor(\.timestamp, order: .reverse)
                case .oldestFirst:
                    SortDescriptor(\.timestamp, order: .forward)
                }

                let descriptor = FetchDescriptor<JournalEntry>(
                    sortBy: [sortOrder]
                )
                return try modelContext.fetch(descriptor)
            }

            logger.info("✅ Fetched \(entries.count) entries")
            return entries
        } catch {
            logger.error("❌ FetchAll failed: \(error.localizedDescription)")
            throw StorageError.persistenceFailure(underlying: error.localizedDescription)
        }
    }

    // MARK: - Protocol Conformance: Fetch by Date Range

    /// Retrieves journal entries within a specific date range.
    ///
    /// Both bounds are inclusive. Results are returned newest first.
    ///
    /// - Parameters:
    ///   - startDate: The beginning of the date range.
    ///   - endDate: The end of the date range.
    /// - Returns: An array of matching `JournalEntry` models, newest first.
    /// - Throws: `StorageError.persistenceFailure` if the fetch operation fails.
    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [JournalEntry] {
        logger.info("📅 fetchEntries(from: \(startDate), to: \(endDate))")

        do {
            let entries: [JournalEntry] = try await MainActor.run {
                let descriptor = FetchDescriptor<JournalEntry>(
                    predicate: #Predicate<JournalEntry> {
                        $0.timestamp >= startDate && $0.timestamp <= endDate
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                return try modelContext.fetch(descriptor)
            }

            logger.info("✅ Fetched \(entries.count) entries in date range")
            return entries
        } catch {
            logger.error("❌ Date range fetch failed: \(error.localizedDescription)")
            throw StorageError.persistenceFailure(underlying: error.localizedDescription)
        }
    }

    // MARK: - Protocol Conformance: Text Search

    /// Searches for entries whose transcript contains the given query string.
    ///
    /// The search is case-insensitive and matches partial strings using
    /// SwiftData's `localizedStandardContains` predicate.
    ///
    /// - Parameter query: The text to search for in transcripts.
    /// - Returns: An array of matching `JournalEntry` models, newest first.
    /// - Throws: `StorageError.persistenceFailure` if the search operation fails.
    func searchEntries(matching query: String) async throws -> [JournalEntry] {
        logger.info("🔎 searchEntries(matching: \"\(query)\")")

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.debug("⚠️ Empty search query — returning all entries")
            return try await fetchAll(sortedBy: .newestFirst)
        }

        do {
            let entries: [JournalEntry] = try await MainActor.run {
                let descriptor = FetchDescriptor<JournalEntry>(
                    predicate: #Predicate<JournalEntry> {
                        $0.rawTranscript.localizedStandardContains(query)
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                return try modelContext.fetch(descriptor)
            }

            logger.info("✅ Found \(entries.count) entries matching \"\(query)\"")
            return entries
        } catch {
            logger.error("❌ Search failed: \(error.localizedDescription)")
            throw StorageError.persistenceFailure(underlying: error.localizedDescription)
        }
    }

    // MARK: - Protocol Conformance: Delete

    /// Deletes a journal entry by its unique identifier.
    ///
    /// - Parameter id: The UUID of the entry to delete.
    /// - Throws: `StorageError.entryNotFound` if no entry matches the given ID.
    func delete(byId id: UUID) async throws {
        logger.info("🗑️ delete(byId:) — id: \(id.uuidString)")

        do {
            try await MainActor.run {
                var descriptor = FetchDescriptor<JournalEntry>(
                    predicate: #Predicate<JournalEntry> { $0.id == id }
                )
                descriptor.fetchLimit = 1

                guard let entry = try modelContext.fetch(descriptor).first else {
                    throw StorageError.entryNotFound(id: id)
                }

                modelContext.delete(entry)
                try modelContext.save()
            }
            logger.info("✅ Entry deleted: \(id.uuidString)")
        } catch let error as StorageError {
            throw error
        } catch {
            logger.error("❌ Delete failed: \(error.localizedDescription)")
            throw StorageError.persistenceFailure(underlying: error.localizedDescription)
        }
    }

    // MARK: - Protocol Conformance: Entry Count

    /// Returns the total count of journal entries in the store.
    ///
    /// Uses SwiftData's `fetchCount` for efficiency — does not load
    /// full model objects into memory.
    ///
    /// - Returns: The number of persisted entries.
    /// - Throws: `StorageError.persistenceFailure` if the count operation fails.
    func entryCount() async throws -> Int {
        logger.info("🔢 entryCount()")

        do {
            let count: Int = try await MainActor.run {
                let descriptor = FetchDescriptor<JournalEntry>()
                return try modelContext.fetchCount(descriptor)
            }

            logger.info("✅ Entry count: \(count)")
            return count
        } catch {
            logger.error("❌ Count failed: \(error.localizedDescription)")
            throw StorageError.persistenceFailure(underlying: error.localizedDescription)
        }
    }
}

// MARK: - Semantic Vector Search (RAG)

extension StorageService {

    /// Finds journal entries semantically similar to a query embedding vector.
    ///
    /// Performs an in-memory cosine similarity ranking across all stored entries
    /// that have non-empty `vectorEmbedding` arrays. Returns the top-K most
    /// similar entries along with their similarity scores.
    ///
    /// This is the core retrieval primitive for RAG (Retrieval-Augmented
    /// Generation) workflows in the VoiceVault pipeline.
    ///
    /// ## Algorithm
    /// 1. Fetches all entries from SwiftData.
    /// 2. Filters to entries with non-empty embeddings.
    /// 3. Computes cosine similarity between each entry's vector and the query vector.
    /// 4. Sorts by similarity (highest first) and returns the top K.
    ///
    /// ## Performance
    /// Linear scan of all entries — O(N × D) where N = entry count and
    /// D = embedding dimensionality. Efficient for hackathon-scale datasets
    /// (< 10,000 entries). For larger datasets, consider a dedicated vector index.
    ///
    /// - Parameters:
    ///   - queryVector: The embedding vector to search against.
    ///   - topK: The maximum number of results to return. Defaults to 5.
    /// - Returns: An array of `(entry: JournalEntry, similarity: Double)` tuples,
    ///   sorted by descending similarity score.
    /// - Throws: `StorageError.persistenceFailure` if the fetch fails.
    func findSimilarEntries(
        to queryVector: [Double],
        topK: Int = 5
    ) async throws -> [(entry: JournalEntry, similarity: Double)] {
        logger.info("🧲 findSimilarEntries(topK: \(topK)) — query vector dims: \(queryVector.count)")

        guard !queryVector.isEmpty else {
            logger.error("❌ Empty query vector provided")
            throw StorageError.persistenceFailure(underlying: "Cannot search with an empty query vector")
        }

        // 1. Fetch all entries
        let allEntries = try await fetchAll(sortedBy: .newestFirst)

        // 2. Filter to entries with compatible embeddings
        let candidates = allEntries.filter {
            !$0.vectorEmbedding.isEmpty && $0.vectorEmbedding.count == queryVector.count
        }

        logger.debug("🔍 \(candidates.count) of \(allEntries.count) entries have compatible embeddings")

        // 3. Compute cosine similarity for each candidate
        var scored: [(entry: JournalEntry, similarity: Double)] = []

        for entry in candidates {
            let similarity = cosineSimilarity(
                between: queryVector,
                and: entry.vectorEmbedding
            )
            scored.append((entry: entry, similarity: similarity))
        }

        // 4. Sort by similarity descending and take top K
        let results = scored
            .sorted { $0.similarity > $1.similarity }
            .prefix(topK)

        logger.info("✅ Found \(results.count) similar entries (top score: \(results.first?.similarity ?? 0.0))")
        return Array(results)
    }

    // MARK: - Private: Cosine Similarity

    /// Computes the cosine similarity between two vectors.
    ///
    /// Returns 0.0 for zero-magnitude vectors or dimension mismatches
    /// (fails gracefully for the search use case).
    ///
    /// - Parameters:
    ///   - vectorA: First embedding vector.
    ///   - vectorB: Second embedding vector.
    /// - Returns: Cosine similarity in `[-1.0, 1.0]`.
    private func cosineSimilarity(between vectorA: [Double], and vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else {
            return 0.0
        }

        let dotProduct = zip(vectorA, vectorB).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(vectorA.reduce(0.0) { $0 + $1 * $1 })
        let magnitudeB = sqrt(vectorB.reduce(0.0) { $0 + $1 * $1 })

        guard magnitudeA > 0, magnitudeB > 0 else {
            return 0.0
        }

        return dotProduct / (magnitudeA * magnitudeB)
    }
}
