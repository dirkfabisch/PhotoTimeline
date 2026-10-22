import SwiftUI

struct SettingsView: View {
    @AppStorage(DateGranularity.defaultsKey) private var granularity: DateGranularity = .all

    var body: some View {
        Form {
            Picker("Datum beim Verschieben ändern:", selection: $granularity) {
                ForEach(DateGranularity.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text("Standard für neue Dokumente. Pro Dokument in der Symbolleiste änderbar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
