import AppIntents
import SwiftUI
import WidgetKit

/// The same one button as the control, for the places a control cannot go:
/// among the app icons on the Home Screen, and in the small round slots on the
/// Lock Screen.
///
/// It shows nothing about any note, which is the point. There is no App Group
/// here and no snapshot of your writing living outside the app — the widget
/// knows how to ask for a new note and nothing else at all.
struct NewNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.espertini.dexEdit.newNoteWidget",
            provider: Unchanging()
        ) { _ in
            NewNoteWidgetView()
        }
        .configurationDisplayName("New Note")
        .description("One tap to start writing.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

/// A timeline of one entry that never expires. WidgetKit insists on a
/// provider; this widget has nothing whatsoever to say that changes, so it says
/// it once and is never asked again.
private struct Unchanging: TimelineProvider {
    struct Entry: TimelineEntry { let date = Date() }

    func placeholder(in context: Context) -> Entry { Entry() }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry()], policy: .never))
    }
}

private struct NewNoteWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Tinted by the system to match the Lock Screen, so the mark is
            // drawn in one colour and left to it.
            Button(intent: NewNoteIntent()) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .containerBackground(.clear, for: .widget)

        case .accessoryRectangular:
            Button(intent: NewNoteIntent()) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                    Text("New note")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .containerBackground(.clear, for: .widget)

        default:
            Button(intent: NewNoteIntent()) {
                VStack(alignment: .leading, spacing: 10) {
                    Mark()
                    Spacer(minLength: 0)
                    Text("New note")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Start writing")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { Brand.indigo }
        }
    }
}

/// The app's own mark, drawn rather than shipped as an image: at this size a
/// hash and a cursor are two shapes, and drawing them keeps the widget one
/// small bundle with nothing to load.
private struct Mark: View {
    var body: some View {
        HStack(spacing: 3) {
            Text("#")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Brand.amber)
                .frame(width: 4, height: 26)
        }
    }
}

/// The two colours the icon is built from, so the widget reads as the app at a
/// glance rather than as a system control.
enum Brand {
    static let indigo = Color(red: 0.31, green: 0.275, blue: 0.898)
    static let amber = Color(red: 0.961, green: 0.651, blue: 0.137)
}
