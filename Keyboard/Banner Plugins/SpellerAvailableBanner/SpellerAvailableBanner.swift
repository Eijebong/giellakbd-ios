import Foundation

final class SpellerAvailableBanner: Banner {
    weak var delegate: UpdateBannerDelegate?
    private let bannerView: SpellerAvailableBannerView
    private let ipc = IPC()

    var view: UIView {
        bannerView
    }

    init(theme: ThemeType) {
        bannerView = SpellerAvailableBannerView(theme: theme)
    }

    func updateTheme(_ theme: ThemeType) {
        bannerView.updateTheme(theme)
    }
}
