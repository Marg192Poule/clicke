import SwiftUI

struct HistorySectionView: View {
    @Binding var saveHistory: Bool
    @Binding var maxHistoryEntries: Int?
    
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Save History", isOn: $saveHistory)
                    Text("Save screenshots for later access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            
            if saveHistory {
                Label {
                    HStack {
                        Text("Maximum number of entries")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { maxHistoryEntries ?? 0 },
                            set: { newValue in
                                maxHistoryEntries = newValue == 0 ? nil : newValue
                            }
                        )) {
                            Text("Unlimited").tag(0)
                            Text("50").tag(50)
                            Text("100").tag(100)
                            Text("200").tag(200)
                            Text("500").tag(500)
                            Text("1000").tag(1000)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                } icon: {
                    Image(systemName: "number.square")
                }
                
                if maxHistoryEntries != nil {
                    Text("The oldest entries will be automatically deleted when the limit is reached")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
                }
            }
        } header: {
            Text("History")
        } footer: {
            if !saveHistory {
                Text("When disabled, screenshots will not be saved.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

