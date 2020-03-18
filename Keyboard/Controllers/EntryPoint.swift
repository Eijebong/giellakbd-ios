import BaseKeyboard

final class EntryKeyboard: KeyboardViewController {
    private var bannerPlugin: DivvunSpellBanner?
    private var showsBanner = true

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(withBanner: showsBanner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if showsBanner {
            bannerPlugin = DivvunSpellBanner(keyboard: self)
        }
    }
}
