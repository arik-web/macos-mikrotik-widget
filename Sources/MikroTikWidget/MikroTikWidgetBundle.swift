import SwiftUI
import WidgetKit

struct MikroTikTrafficWidget: Widget {
    static let kind = "MikroTikTrafficWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TrafficTimelineProvider()) { entry in
            TrafficWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Router Traffic")
        .description("Live WAN status and throughput for the MikroTik router.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// The entry point is compiled only into the real extension; SwiftPM builds
// these sources as a plain library to type-check them, and a library must not
// declare a `main`.
#if MIKROTIK_WIDGET_EXTENSION
@main
struct MikroTikWidgetBundle: WidgetBundle {
    var body: some Widget {
        MikroTikTrafficWidget()
    }
}
#endif
