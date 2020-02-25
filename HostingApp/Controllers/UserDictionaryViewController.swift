import UIKit

class UserDictionaryViewController: ViewController<UserDictionaryView> {
    private let userDictionary = UserDictionary()
    private var userWords: [String] {
        userDictionary.getUserWords(locale: keyboardLocale)
    }
    private var isEmpty: Bool { userWords.count == 0 }
    private let keyboardLocale: KeyboardLocale

    private var tableView: UITableView {
        contentView.tableView!
    }

    init(keyboardLocale: KeyboardLocale) {
        self.keyboardLocale = keyboardLocale
        super.init()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        deselectSelectedRow()
    }

    private func setupView() {
        setupNavBar()

        if isEmpty {
            showEmptyState()
        } else {
            setupTableView()
        }
    }

    private func setupNavBar() {
        title = Strings.userDictionary
        let plusButton = UIBarButtonItem.init(barButtonSystemItem: .add, target: self, action: #selector(showAddWordAlert))
        navigationItem.rightBarButtonItem = plusButton
    }

    @objc private func showAddWordAlert() {
        let title = "Add Word" // LOCALIZE ME
        let message = "This word will be suggested in the spelling banner for similar input." // LOCALIZE ME
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.placeholder = "Word"
        }

        // LOCALIZE
        let addAction = UIAlertAction(title: "Add", style: .default) { _ in
            guard let word = alert.textFields?.first?.text else {
                return
            }
            self.userDictionary.addUserWord(word, locale: self.keyboardLocale)
            self.tableView.reloadData()
        }

        alert.addAction(addAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        self.present(alert, animated: true)
    }

    private func showEmptyState() {
        tableView.isHidden = true
    }

    private func setupTableView() {
        tableView.isHidden = false
        tableView.register(DisclosureCell.self)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
    }

    private func deselectSelectedRow() {
        if let selectedRowPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectedRowPath, animated: true)
        }
    }
}

extension UserDictionaryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return userWords.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(DisclosureCell.self)
        cell.textLabel?.text = userWords[indexPath.item]
        return cell
    }
}

extension UserDictionaryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let word = userWords[indexPath.row]
        let wordController = WordContextViewController(dictionary: userDictionary, word: word)
        navigationController?.pushViewController(wordController, animated: true)
    }
}
