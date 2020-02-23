import Foundation
import SQLite

private let userWordsTableName = "user_word"
private let wordContextTableName = "word_context"

public class UserDictionary {
    private enum WordState: String {
        case candidate
        case userWord = "user_word"
        case manuallyAdded = "manually_added"
        case blacklisted
    }

    private let userWords = Table(userWordsTableName)
    private let wordIdCol = Expression<Int64>("id")
    private let wordCol = Expression<String>("word")
    private let localeCol = Expression<String>("locale")
    private let stateCol = Expression<String>("state")

    private let wordContext = Table(wordContextTableName)
    private let contextId = Expression<Int64>("id")
    private let wordIdForeignKey = Expression<Int64>("word_id")
    private let secondBefore = Expression<String?>("second_before")
    private let firstBefore = Expression<String?>("first_before")
    private let firstAfter = Expression<String?>("first_after")
    private let secondAfter = Expression<String?>("second_after")

    private lazy var dbFilePath: String = {
        let groupId = "group.no.divvun.GiellaKeyboardDylan"
        let dbFileName = "userDictionary.sqlite3"

        guard let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            fatalError("Error opening app group for group id: \(groupId)")
        }

        return "\(groupUrl)\(dbFileName)"
    }()

    private lazy var database: Connection = {
        guard let database = try? Connection(dbFilePath) else {
            fatalError("Unable to create or open user dictionary database")
        }
        try? database.execute("PRAGMA foreign_keys = ON;")
        createTablesIfNeeded(database: database)
        return database
    }()

    private func createTablesIfNeeded(database: Connection) {
        do {
            try createUserWordTable(database: database)
            try createWordContextTable(database: database)
        } catch {
            fatalError("Error creating database table: \(error)")
        }
    }

    private func createUserWordTable(database: Connection) throws {
        try database.run(userWords.create(ifNotExists: true) { table in
            table.column(wordIdCol, primaryKey: true)
            table.column(wordCol, collate: .nocase)
            table.column(localeCol)
            table.column(stateCol)
        })
    }

    private func createWordContextTable(database: Connection) throws {
        try database.run(wordContext.create(ifNotExists: true) { table in
            table.column(contextId, primaryKey: true)
            table.column(wordIdForeignKey)
            table.column(secondBefore)
            table.column(firstBefore)
            table.column(firstAfter)
            table.column(secondAfter)
            table.foreignKey(wordIdForeignKey, references: userWords, wordIdCol, delete: .cascade)
        })
    }

    public func add(word: String, locale: KeyboardLocale) {
        add(context: WordContext(word: word), locale: locale)
    }

    public func add(context: WordContext, locale: KeyboardLocale) {
        validateContext(context)

        let word = context.word
        let wordId: Int64

        if let existingWord = fetchWord(word, locale: locale) {
            wordId = existingWord[wordIdCol]
            if wordIsCandidate(existingWord) {
                updateWordState(id: wordId, state: .userWord)
            }
        } else {
            wordId = insertWordCandidate(word: word, locale: locale)
        }

        insertContext(context, for: wordId)
    }

    public func removeWord(_ word: String, locale: KeyboardLocale) {
        do {
            let query = userWords.filter(wordCol == word)
            try database.run(query.delete())
        } catch {
            fatalError("Error deleting word from UserDictionary \(error)")
        }
    }

    private func validateContext(_ context: WordContext) {
        if context.secondBefore != nil && context.firstBefore == nil {
            fatalError("Attempted to add word to UserDictionary with secondBefore word but no firstBefore word.")
        }
        if context.secondAfter != nil && context.firstAfter == nil {
            fatalError("Attempted to add word to UserDictionary with secondAfter word but no firstAfter word.")
        }
    }

    private func wordIsCandidate(_ row: SQLite.Row) -> Bool {
        let wordState = WordState(rawValue: row[stateCol])
        return wordState == .candidate
    }

    private func fetchWord(_ word: String, locale: KeyboardLocale) -> SQLite.Row? {
        var row: SQLite.Row?
        do {
            let query = userWords.filter(wordCol == word)
            row = try database.pluck(query)
        } catch {
            fatalError("Error finding existsing word: \(error)")
        }
        return row
    }

    private func updateWordState(id: Int64, state: WordState) {
        do {
            let word = userWords.filter(wordIdCol == id)
            try database.run(word.update(stateCol <- state.rawValue))
        } catch {
            fatalError("Error updating word state \(error)")
        }
    }

    @discardableResult
    private func insertWordCandidate(word: String, locale: KeyboardLocale) -> Int64 {
        return insertWord(word: word, locale: locale, state: .candidate)
    }

    public func addWordManually(_ word: String, locale: KeyboardLocale) {
        if let existingWord = fetchWord(word, locale: locale) {
            updateWordState(id: existingWord[wordIdCol], state: .manuallyAdded)
        } else {
            let wordId = insertWord(word: word, locale: locale, state: .manuallyAdded)
            insertContext(WordContext(word: word), for: wordId)
        }
    }

    @discardableResult
    private func insertWord(word: String, locale: KeyboardLocale, state: WordState) -> Int64 {
        let insert = userWords.insert(
            wordCol <- word.lowercased(),
            localeCol <- locale.identifier,
            stateCol <- state.rawValue
        )

        do {
            return try database.run(insert)
        } catch {
            fatalError("Error inserting into database: \(error)")
        }
    }

    private func insertContext(_ context: WordContext, for wordId: Int64) {
        let insert = wordContext.insert(
            wordIdForeignKey <- wordId,
            secondBefore <- context.secondBefore,
            firstBefore <- context.firstBefore,
            firstAfter <- context.firstAfter,
            secondAfter <- context.secondAfter
        )
        do {
            try database.run(insert)
        } catch {
            fatalError("Error inserting context into database: \(error)")
        }
    }

    public func getUserWords(locale: KeyboardLocale) -> [String] {
        var words: [String] = []
        let query = userWords.select(wordCol)
            .filter(localeCol == locale.identifier)
            .filter(stateCol == WordState.userWord.rawValue || stateCol == WordState.manuallyAdded.rawValue)
            .order(wordCol)
        do {
            let rows = try database.prepare(query)
            for row in rows {
                let word = row[wordCol]
                words.append(word)
            }
        } catch {
            print("Error getting user words: \(error)")
        }
        return words
    }

    public func getContexts(for word: String, locale: KeyboardLocale) -> [WordContext] {
        guard let wordRow = fetchWord(word, locale: locale) else {
            return []
        }

        let wordId = wordRow[wordIdCol]
        let query = wordContext.filter(wordIdForeignKey == wordId)
        do {
            let rows = try database.prepare(query)
            return rows.map({
                WordContext(secondBefore: $0[secondBefore],
                            firstBefore: $0[firstBefore],
                            word: word,
                            firstAfter: $0[firstAfter],
                            secondAfter: $0[secondAfter])
            })
        } catch {
            fatalError("Error getting user dictionary word contexts: \(error)")
        }
    }
}

// Methods used for testing only
extension UserDictionary {
    public func dropTables() {
        do {
            try database.run(userWords.drop())
            try database.run(wordContext.drop())
        } catch {
            fatalError("Error dropping database tables: \(error)")
        }
    }

    public func addTestRows(locale: KeyboardLocale) {
        let contexts = [
            WordContext(secondBefore: "I", firstBefore: "said", word: "hello"),
            WordContext(firstBefore: "well", word: "hello", firstAfter: "there"),
            WordContext(word: "hello", firstAfter: "to", secondAfter: "you"),
            WordContext(secondBefore: "I", firstBefore: "said", word: "hi"),
            WordContext(firstBefore: "say", word: "hi", firstAfter: "to"),
            WordContext(word: "hi", firstAfter: "there", secondAfter: "Frank")
        ]

        for context in contexts {
            add(context: context, locale: locale)
        }
    }

    public func printDatabaseRows() {
        do {
            print("WORDS TABLE:")
            for row in try database.prepare(userWords) {
                let rowData = "id: \(row[wordIdCol]), "
                    + "word: \(String(describing: row[wordCol])), "
                    + "locale: \(row[localeCol]), "
                    + "state: \(String(describing: row[stateCol])), "
                print(rowData)
            }

            print("\n")
            print("CONTEXT TABLE:")
            for row in try database.prepare(wordContext) {
                let rowData = "id: \(row[contextId]), "
                    + "wordId: \(row[wordIdForeignKey]), "
                    + "secondBefore: \(String(describing: row[secondBefore])), "
                    + "firstBefore: \(String(describing: row[firstBefore])), "
                    + "firstAfter: \(String(describing: row[firstAfter])), "
                    + "secondAfter: \(String(describing: row[secondAfter]))"
                print(rowData)
            }

        } catch {
            print("Error printing database: \(error)")
        }
    }

    public func getWordDatabaseRows() -> [SQLite.Row] {
        return getDatabaseRows(for: userWords)
    }

    public func getContextDatabaseRows() -> [SQLite.Row] {
        return getDatabaseRows(for: wordContext)
    }

    private func getDatabaseRows(for table: Table) -> [SQLite.Row] {
        do {
            return try Array(database.prepare(table))
        } catch {
            fatalError("Error getting word database Rows")
        }
    }
}
