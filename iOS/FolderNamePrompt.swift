import SwiftUI

/// The name-a-folder sheet, used for both creating and renaming.
///
/// A sheet rather than an alert with a text field: on iPad the alert flavour is
/// cramped, and this one can carry a sentence of explanation.
struct FolderNamePrompt: View {
    let title: String
    let message: String
    let confirm: String
    @State var name: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SelectAllTextField(
                        placeholder: "Folder name",
                        text: $name,
                        onSubmit: apply
                    )
                    .frame(height: 24)
                } footer: {
                    Text(message)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm, action: apply)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private func apply() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        onConfirm(cleaned)
        dismiss()
    }
}
