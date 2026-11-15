import SwiftUI

@main
struct BenchHostApp: App {
    var body: some Scene { WindowGroup { InputView() } }
}

/// One text box and nothing else: the UI test types into it with the system keyboard and reads it back.
struct InputView: View {
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading) {
            TextField("", text: $text, axis: .vertical)
                .accessibilityIdentifier("input")
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .border(.gray)
            Button("clear") { text = "" }.accessibilityIdentifier("clear")
            Spacer()
        }
        .padding()
        .onAppear { focused = true }
    }
}
