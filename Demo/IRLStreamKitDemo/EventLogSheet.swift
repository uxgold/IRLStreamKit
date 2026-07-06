import SwiftUI

struct EventLogSheet: View {
    let entries: [DemoModel.LogEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                        Text(entry.text)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .listRowSeparator(.hidden)
                    .id(entry.id)
                }
                .listStyle(.plain)
                .onAppear {
                    if let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Events (\(entries.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
