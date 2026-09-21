import SwiftUI

struct HistoryRetentionSettings: View {
  @ObservedObject var configuration: AppConfiguration
  @Environment(\.dismiss) private var dismiss
  @State private var days = ""

  private var validDays: Int? {
    guard let value = Int(days), (1...36_500).contains(value) else { return nil }
    return value
  }

  var body: some View {
    Form {
      Section {
        HStack {
          Text("Keep for")
          Spacer()
          TextField("30", text: $days)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 60, maxWidth: 100)
            .accessibilityLabel("Days to keep history")
            .accessibilityIdentifier("history-retention-days")
          Text("days").foregroundStyle(.secondary)
        }
      } footer: {
        Text("Notes, dictations, translations, and photo text older than this are removed automatically. Shortening this period removes older text when you save. Recordings waiting for retry are kept separately.")
      }
      if !days.isEmpty, validDays == nil {
        Text("Enter a whole number from 1 to 36,500.")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Keep History")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          guard let value = validDays else { return }
          configuration.historyRetentionDays = value
          dismiss()
        }
        .disabled(validDays == nil)
        .accessibilityIdentifier("save-history-retention-button")
      }
    }
    .onAppear { days = String(configuration.historyRetentionDays) }
  }
}
