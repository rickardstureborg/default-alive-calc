import DefaultAliveCore
import SwiftUI

/// "Add more…": every place with a checkbox, filtered on each keystroke (TaxCatalog.matching:
/// name, state name or state code). A state shown with its cities heads them; a city shown
/// without its state reads "Seattle, WA". Ticking adds and unticking removes, straight away;
/// "Add all" / "Remove all" act on what the filter shows. Twin of taxPicker() in
/// design/index.html.
///
/// It's a popover, so a window of its own: the app's key monitor only watches the main
/// window, which is why typing "c" in the filter types a c, and Esc closes the popover
/// instead of clearing the form.
struct TaxPicker: View {
    @Binding var state: CalculatorState
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        let shown = TaxCatalog.matching(query)
        let shownStates = Set(shown.filter { !$0.local }.map(\.state))
        VStack(alignment: .leading, spacing: 6) {
            TextField("Filter states and cities", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
            HStack(spacing: 12) {
                link("Add all", help: query.isEmpty ? "Add every place" : "Add every place shown") {
                    state.setTaxPlaces(shown.map(\.id), included: true)
                }
                link("Remove all", help: query.isEmpty ? "Remove every place" : "Remove every place shown") {
                    state.setTaxPlaces(shown.map(\.id), included: false)
                }
            }
            .font(.system(size: 11))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { place in
                        row(place, nested: place.local && shownStates.contains(place.state))
                    }
                }
            }
            .frame(height: 248)
            Text("\(TaxCatalog.nothingOwed.count) more cities checked owe nothing before profit.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help(TaxCatalog.nothingOwed.joined(separator: ", "))
        }
        .font(.system(size: 12))
        .padding(10)
        .frame(width: 300)
        .onAppear { filterFocused = true }
    }

    private func row(_ place: TaxPlace, nested: Bool) -> some View {
        let on = Binding(get: { state.taxPlaces.contains(place.id) },
                         set: { state.setTaxPlace(place.id, included: $0) })
        return Toggle(isOn: on) {
            HStack(spacing: 8) {
                Text(place.local && !nested ? "\(place.name), \(place.state)" : place.name)
                    .fontWeight(place.local ? .regular : .semibold)
                Spacer(minLength: 0)
                Text(placeSummary(place, short: true))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        .toggleStyle(.checkbox)
        .focusable(false)
        .padding(.leading, nested ? 20 : 0)
        .padding(.vertical, 2)
        .padding(.top, place.local ? 0 : 3)
        .help(place.note)
    }

    private func link(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).underline(true, pattern: .dot, color: .secondary)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .focusable(false)
        .help(help)
    }
}
