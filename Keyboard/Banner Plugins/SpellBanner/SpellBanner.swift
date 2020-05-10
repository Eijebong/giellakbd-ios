import Foundation
import Sentry
import DivvunSpell

typealias SuggestionCompletion = ([String]) -> Void

protocol SpellBannerDelegate: class {
    var hasFullAccess: Bool { get }
    func didSelectSuggestion(banner: SpellBanner, suggestion: String)
}

public final class SpellBanner: Banner {
    weak var delegate: SpellBannerDelegate?
    private var dictionaryService: UserDictionaryService?
    private var speller: ThfstChunkedBoxSpeller?
    private let bannerView: SpellBannerView
    private let opQueue: OperationQueue = {
        let opQueue = OperationQueue()
        opQueue.underlyingQueue = DispatchQueue.global(qos: .userInteractive)
        opQueue.maxConcurrentOperationCount = 1
        return opQueue
    }()

    var view: UIView {
        bannerView
    }

    var spellerURL: URL? {
        let spellerPackagesDir = KeyboardSettings.pahkatStoreURL
            .appendingPathComponent("pkg")

        let currentKeyboard = Bundle.main

        guard let spellerKey = currentKeyboard.spellerPackageKey,
            let url = URL(string: spellerKey),
            let packageId = url.pathComponents.last
        else {
            print("No speller package key found; BHFST not loaded.")
            return nil
        }
        
        guard let spellerPath = currentKeyboard.spellerPath else {
            print("No speller path found; BHFST not loaded.")
            return nil
        }

        return spellerPackagesDir
            .appendingPathComponent(packageId)
            .appendingPathComponent(spellerPath)
    }

    var spellerNeedsInstall: Bool {
        guard let spellerURL = spellerURL else {
            return false
        }
        let hasSpeller = FileManager.default.fileExists(atPath: spellerURL.path)
        return hasSpeller == false
    }

    init(theme: ThemeType) {
        self.bannerView = SpellBannerView(theme: theme)
        bannerView.delegate = self
        loadSpeller()
    }

    public func updateSuggestions(_ context: CursorContext) {
        if let delegate = delegate,
            delegate.hasFullAccess {
            dictionaryService?.updateContext(WordContext(cursorContext: context))
        }

        let currentWord = context.current.1

        if currentWord.isEmpty {
            bannerView.clearSuggestions()
            return
        }

        getSuggestionsFor(currentWord) { (suggestions) in
            let suggestionItems = self.makeSuggestionBannerItems(currentWord: currentWord, suggestions: suggestions)
            self.bannerView.isHidden = false
            self.bannerView.setBannerItems(suggestionItems)
        }
    }

    private func getSuggestionsFor(_ word: String, completion: @escaping SuggestionCompletion) {
        opQueue.cancelAllOperations()
        let dictionary = self.dictionaryService?.dictionary
        let speller = self.speller
        let suggestionOp = SuggestionOperation(userDictionary: dictionary, speller: speller, word: word, completion: completion)
        opQueue.addOperation(suggestionOp)
    }

    private func makeSuggestionBannerItems(currentWord: String, suggestions: [String]) -> [SpellBannerItem] {
        let currentWordItem = SpellBannerItem(title: "\"\(currentWord)\"", value: currentWord)

        var suggestions = suggestions
        suggestions.removeAll { $0 == currentWord } // don't show current word twice
        let suggestionItems = suggestions.map { SpellBannerItem(title: $0, value: $0) }

        return [currentWordItem] + suggestionItems
    }

    func updateTheme(_ theme: ThemeType) {
        bannerView.updateTheme(theme)
    }

    public func loadSpeller() {
        print("Loading speller…")

        DispatchQueue.global(qos: .background).async {
            print("Dispatching request to load speller…")

            guard let spellerPath = self.spellerURL?.path else {
                print("Unable to get spellerURL; BHFST not loaded")
                return
            }

            if !FileManager.default.fileExists(atPath: spellerPath) {
                print("No speller at: \(spellerPath)")
                print("DivvunSpell **not** loaded.")
                return
            }

            let speller: ThfstChunkedBoxSpeller
            do {
                let archive = try ThfstChunkedBoxSpellerArchive.open(path: spellerPath)
                speller = try archive.speller()
                self.speller = speller
                print("DivvunSpell loaded!")
            } catch {
                let error = Sentry.Event(level: .error)
                Client.shared?.send(event: error, completion: nil)
                print("DivvunSpell **not** loaded.")
                return
            }

            #if ENABLE_USER_DICTIONARY
            self.dictionaryService = UserDictionaryService(speller: speller, locale: KeyboardLocale.current)
            #endif
        }
    }
}

extension SpellBanner: SpellBannerViewDelegate {
    public func didSelectBannerItem(_ banner: SpellBannerView, item: SpellBannerItem) {
        delegate?.didSelectSuggestion(banner: self, suggestion: item.value)
        opQueue.cancelAllOperations()
        banner.clearSuggestions()
    }
}

final class SuggestionOperation: Operation {
    weak var userDictionary: UserDictionary?
    weak var speller: ThfstChunkedBoxSpeller?
    let word: String
    let completion: SuggestionCompletion

    init(userDictionary: UserDictionary?,
         speller: ThfstChunkedBoxSpeller?,
         word: String,
         completion: @escaping SuggestionCompletion) {
        self.userDictionary = userDictionary
        self.speller = speller
        self.word = word
        self.completion = completion
    }

    override func main() {
        if isCancelled {
            return
        }

        let suggestions = getSuggestions(for: word)
        if !isCancelled {
            DispatchQueue.main.async {
                self.completion(suggestions)
            }
        }
    }

    private func getSuggestions(for word: String) -> [String] {
        var suggestions: [String] = []

        if let dictionary = userDictionary {
            let userSuggestions = dictionary.getSuggestions(for: word)
            suggestions.append(contentsOf: userSuggestions)
        }

        if let speller = speller {
            let spellerSuggestions = (try? speller
                .suggest(word: word)
                .prefix(3)) ?? []
            suggestions.append(contentsOf: spellerSuggestions)
        }

        return suggestions
    }
}
