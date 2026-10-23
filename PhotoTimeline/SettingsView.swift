import SwiftUI

struct SettingsView: View {
    @Bindable var updater: Updater
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

            Divider().padding(.vertical, 8)

            Toggle("Automatisch nach Updates suchen", isOn: $updater.automaticallyChecksForUpdates)
            Text("Fragt einmal täglich bei GitHub nach einer neuen Version. Es werden keine Daten über deinen Mac gesendet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }
}
