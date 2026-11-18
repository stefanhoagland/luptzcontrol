import Foundation

/// A camera setting with a fixed list of choices, sent with Panasonic's aw_cam "O<code>:<value>" commands.
struct ImageSetting: Identifiable {
    struct Choice: Hashable {
        let label: String
        let value: String
    }

    let code: String
    let label: String
    let choices: [Choice]

    var id: String { code }

    func label(for value: String?) -> String? {
        guard let value else { return nil }
        return choices.first { $0.value.caseInsensitiveCompare(value) == .orderedSame }?.label
    }

    static let all: [ImageSetting] = [
        ImageSetting(code: "AW", label: "White balance", choices: [
            Choice(label: "ATW (auto tracking)", value: "0"),
            Choice(label: "AWB A", value: "1"),
            Choice(label: "AWB B", value: "2"),
            Choice(label: "3200K", value: "4"),
            Choice(label: "5600K", value: "5"),
            Choice(label: "VAR", value: "9"),
        ]),
        ImageSetting(code: "GU", label: "Gain", choices:
            [Choice(label: "Auto", value: "80")] +
            stride(from: 0, through: 36, by: 3).map { db in
                Choice(label: "\(db) dB", value: String(format: "%02X", 0x08 + db))
            }
        ),
        ImageSetting(code: "FT", label: "ND filter", choices: [
            Choice(label: "Through", value: "0"),
            Choice(label: "1/4", value: "1"),
            Choice(label: "1/16", value: "2"),
            Choice(label: "1/64", value: "3"),
        ]),
    ]
}
