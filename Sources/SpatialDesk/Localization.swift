import Foundation

private let uiBundle: Bundle = {
    let locale = Locale.preferredLanguages.first?.lowercased() ?? "en"
    let language = locale.hasPrefix("zh") ? "zh-Hans" : "en"
    return Bundle.module.url(forResource: language, withExtension: "lproj")
        .flatMap(Bundle.init(url:)) ?? Bundle.module
}()

func tr(_ key: String) -> String {
    uiBundle.localizedString(forKey: key, value: key, table: nil)
}
