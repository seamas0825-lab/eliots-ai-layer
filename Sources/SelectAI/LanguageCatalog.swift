import Foundation

struct LanguageOption {
    let menuTitle: String
    let promptName: String
}

enum LanguageCatalog {
    // Ethnologue 2025 total-speaker ranking (L1 + L2), in descending order.
    // Ethnologue ranks individual languages rather than macro-languages, so
    // several Chinese and Arabic varieties intentionally appear separately.
    static let ranked100: [LanguageOption] = [
        .init(menuTitle: "English · 英语", promptName: "英语"),
        .init(menuTitle: "中文（普通话）", promptName: "简体中文（普通话）"),
        .init(menuTitle: "हिन्दी · 印地语", promptName: "印地语"),
        .init(menuTitle: "Español · 西班牙语", promptName: "西班牙语"),
        .init(menuTitle: "العربية الفصحى · 标准阿拉伯语", promptName: "标准阿拉伯语"),
        .init(menuTitle: "Français · 法语", promptName: "法语"),
        .init(menuTitle: "বাংলা · 孟加拉语", promptName: "孟加拉语"),
        .init(menuTitle: "Português · 葡萄牙语", promptName: "葡萄牙语"),
        .init(menuTitle: "Русский · 俄语", promptName: "俄语"),
        .init(menuTitle: "Bahasa Indonesia · 印度尼西亚语", promptName: "印度尼西亚语"),
        .init(menuTitle: "اردو · 乌尔都语", promptName: "乌尔都语"),
        .init(menuTitle: "Deutsch · 标准德语", promptName: "标准德语"),
        .init(menuTitle: "日本語 · 日语", promptName: "日语"),
        .init(menuTitle: "Nigerian Pidgin · 尼日利亚皮钦语", promptName: "尼日利亚皮钦语"),
        .init(menuTitle: "العربية المصرية · 埃及阿拉伯语", promptName: "埃及阿拉伯语"),
        .init(menuTitle: "मराठी · 马拉地语", promptName: "马拉地语"),
        .init(menuTitle: "Tiếng Việt · 越南语", promptName: "越南语"),
        .init(menuTitle: "తెలుగు · 泰卢固语", promptName: "泰卢固语"),
        .init(menuTitle: "Hausa · 豪萨语", promptName: "豪萨语"),
        .init(menuTitle: "Türkçe · 土耳其语", promptName: "土耳其语"),
        .init(menuTitle: "پنجابی · 西旁遮普语", promptName: "西旁遮普语"),
        .init(menuTitle: "Kiswahili · 斯瓦希里语", promptName: "斯瓦希里语"),
        .init(menuTitle: "Tagalog · 他加禄语", promptName: "他加禄语"),
        .init(menuTitle: "தமிழ் · 泰米尔语", promptName: "泰米尔语"),
        .init(menuTitle: "粵語 · 粤语", promptName: "粤语"),
        .init(menuTitle: "吴语", promptName: "吴语"),
        .init(menuTitle: "فارسی · 伊朗波斯语", promptName: "伊朗波斯语"),
        .init(menuTitle: "한국어 · 韩语", promptName: "韩语"),
        .init(menuTitle: "ไทย · 泰语", promptName: "泰语"),
        .init(menuTitle: "Basa Jawa · 爪哇语", promptName: "爪哇语"),
        .init(menuTitle: "Italiano · 意大利语", promptName: "意大利语"),
        .init(menuTitle: "ગુજરાતી · 古吉拉特语", promptName: "古吉拉特语"),
        .init(menuTitle: "Levantine Arabic · 黎凡特阿拉伯语", promptName: "黎凡特阿拉伯语"),
        .init(menuTitle: "አማርኛ · 阿姆哈拉语", promptName: "阿姆哈拉语"),
        .init(menuTitle: "ಕನ್ನಡ · 卡纳达语", promptName: "卡纳达语"),
        .init(menuTitle: "भोजपुरी · 博杰普尔语", promptName: "博杰普尔语"),
        .init(menuTitle: "Sudanese Arabic · 苏丹阿拉伯语", promptName: "苏丹阿拉伯语"),
        .init(menuTitle: "Yorùbá · 约鲁巴语", promptName: "约鲁巴语"),
        .init(menuTitle: "晋语", promptName: "晋语"),
        .init(menuTitle: "闽南语", promptName: "闽南语"),
        .init(menuTitle: "Polski · 波兰语", promptName: "波兰语"),
        .init(menuTitle: "မြန်မာဘာသာ · 缅甸语", promptName: "缅甸语"),
        .init(menuTitle: "Algerian Arabic · 阿尔及利亚阿拉伯语", promptName: "阿尔及利亚阿拉伯语"),
        .init(menuTitle: "客家话", promptName: "客家话"),
        .init(menuTitle: "Lingála · 林加拉语", promptName: "林加拉语"),
        .init(menuTitle: "Moroccan Arabic · 摩洛哥阿拉伯语", promptName: "摩洛哥阿拉伯语"),
        .init(menuTitle: "ଓଡ଼ିଆ · 奥里亚语", promptName: "奥里亚语"),
        .init(menuTitle: "Українська · 乌克兰语", promptName: "乌克兰语"),
        .init(menuTitle: "湘语", promptName: "湘语"),
        .init(menuTitle: "മലയാളം · 马拉雅拉姆语", promptName: "马拉雅拉姆语"),
        .init(menuTitle: "سنڌي · 信德语", promptName: "信德语"),
        .init(menuTitle: "ਪੰਜਾਬੀ · 东旁遮普语", promptName: "东旁遮普语"),
        .init(menuTitle: "Basa Sunda · 巽他语", promptName: "巽他语"),
        .init(menuTitle: "Igbo · 伊博语", promptName: "伊博语"),
        .init(menuTitle: "دری · 达里语", promptName: "达里语"),
        .init(menuTitle: "नेपाली · 尼泊尔语", promptName: "尼泊尔语"),
        .init(menuTitle: "Bahasa Melayu · 马来语", promptName: "马来语"),
        .init(menuTitle: "Oʻzbekcha · 北乌兹别克语", promptName: "北乌兹别克语"),
        .init(menuTitle: "isiZulu · 祖鲁语", promptName: "祖鲁语"),
        .init(menuTitle: "Sa'idi Arabic · 赛义迪阿拉伯语", promptName: "赛义迪阿拉伯语"),
        .init(menuTitle: "پښتو · 北部普什图语", promptName: "北部普什图语"),
        .init(menuTitle: "Afaan Oromoo · 西中部奥罗莫语", promptName: "西中部奥罗莫语"),
        .init(menuTitle: "سرائیکی · 萨拉基语", promptName: "萨拉基语"),
        .init(menuTitle: "Nederlands · 荷兰语", promptName: "荷兰语"),
        .init(menuTitle: "Soomaali · 索马里语", promptName: "索马里语"),
        .init(menuTitle: "Română · 罗马尼亚语", promptName: "罗马尼亚语"),
        .init(menuTitle: "অসমীয়া · 阿萨姆语", promptName: "阿萨姆语"),
        .init(menuTitle: "赣语", promptName: "赣语"),
        .init(menuTitle: "پښتو · 南部普什图语", promptName: "南部普什图语"),
        .init(menuTitle: "Cebuano · 宿务语", promptName: "宿务语"),
        .init(menuTitle: "Қазақша · 哈萨克语", promptName: "哈萨克语"),
        .init(menuTitle: "मगही · 摩揭陀语", promptName: "摩揭陀语"),
        .init(menuTitle: "Najdi Arabic · 纳吉迪阿拉伯语", promptName: "纳吉迪阿拉伯语"),
        .init(menuTitle: "සිංහල · 僧伽罗语", promptName: "僧伽罗语"),
        .init(menuTitle: "Mesopotamian Arabic · 美索不达米亚阿拉伯语", promptName: "美索不达米亚阿拉伯语"),
        .init(menuTitle: "isiXhosa · 科萨语", promptName: "科萨语"),
        .init(menuTitle: "ខ្មែរ · 高棉语", promptName: "高棉语"),
        .init(menuTitle: "Afrikaans · 南非荷兰语", promptName: "南非荷兰语"),
        .init(menuTitle: "Nigerian Fulfulde · 尼日利亚富拉语", promptName: "尼日利亚富拉语"),
        .init(menuTitle: "मैथिली · 迈蒂利语", promptName: "迈蒂利语"),
        .init(menuTitle: "Wolof · 沃洛夫语", promptName: "沃洛夫语"),
        .init(menuTitle: "Kurmancî · 北库尔德语", promptName: "北库尔德语"),
        .init(menuTitle: "छत्तीसगढ़ी · 恰蒂斯加尔语", promptName: "恰蒂斯加尔语"),
        .init(menuTitle: "Ikinyarwanda · 卢旺达语", promptName: "卢旺达语"),
        .init(menuTitle: "ภาษาอีสาน · 东北泰语", promptName: "东北泰语"),
        .init(menuTitle: "Chichewa · 齐切瓦语", promptName: "齐切瓦语"),
        .init(menuTitle: "Bamanankan · 班巴拉语", promptName: "班巴拉语"),
        .init(menuTitle: "chiShona · 修纳语", promptName: "修纳语"),
        .init(menuTitle: "Güney Azərbaycan dili · 南阿塞拜疆语", promptName: "南阿塞拜疆语"),
        .init(menuTitle: "Setswana · 茨瓦纳语", promptName: "茨瓦纳语"),
        .init(menuTitle: "Sesotho sa Leboa · 北索托语", promptName: "北索托语"),
        .init(menuTitle: "Boarisch · 巴伐利亚语", promptName: "巴伐利亚语"),
        .init(menuTitle: "Kreyòl ayisyen · 海地克里奥尔语", promptName: "海地克里奥尔语"),
        .init(menuTitle: "ئۇيغۇرچە · 维吾尔语", promptName: "维吾尔语"),
        .init(menuTitle: "Sesotho · 南索托语", promptName: "南索托语"),
        .init(menuTitle: "Ελληνικά · 希腊语", promptName: "希腊语"),
        .init(menuTitle: "Svenska · 瑞典语", promptName: "瑞典语"),
        .init(menuTitle: "চাটগাঁইয়া · 吉大港语", promptName: "吉大港语"),
        .init(menuTitle: "Ikirundi · 隆迪语", promptName: "隆迪语"),
        .init(menuTitle: "Julakan · 朱拉语", promptName: "朱拉语")
    ]

    static let outputLanguageNames = ranked100.map(\.promptName)

    static func numberedTitle(for language: LanguageOption, at index: Int) -> String {
        "\(index + 1). \(language.menuTitle)"
    }

    static func normalizedOutputLanguage(_ value: String) -> String {
        switch value {
        case "简体中文", "中文（普通话）": return "简体中文（普通话）"
        case "English": return "英语"
        case "日本語": return "日语"
        default: return outputLanguageNames.contains(value) ? value : "简体中文（普通话）"
        }
    }
}
