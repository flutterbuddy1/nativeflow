import ActivityKit
import SwiftUI
import WidgetKit

// Must match the plugin's type exactly: ActivityKit pairs app and widget
// extension by this type's name and Codable shape.
struct NativeFlowActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable { var values: [String: String] }
  var values: [String: String]
}

let appGroup = "group.com.example.nativeflowExample"

@main
struct NativeFlowWidgets: WidgetBundle {
  var body: some Widget {
    TripLiveActivity()
    DriverStatusWidget()
  }
}

// MARK: - Live Activity (NativeFlow.activities / NativeFlow.present)

struct TripLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NativeFlowActivityAttributes.self) { ctx in
      let v = ctx.state.values
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(v["title"] ?? v["status"] ?? "Trip").font(.headline)
          Text(v["body"] ?? "Rider: \(ctx.attributes.values["rider"] ?? "-")").font(.subheadline)
          if let p = Double(v["progress"] ?? "") { ProgressView(value: p) }
        }
        Spacer()
        Text(v["eta"] ?? "").font(.title2).bold()
      }
      .padding()
    } dynamicIsland: { ctx in
      let v = ctx.state.values
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Text(v["status"] ?? v["title"] ?? "") }
        DynamicIslandExpandedRegion(.trailing) { Text(v["eta"] ?? "") }
        DynamicIslandExpandedRegion(.bottom) { Text(v["body"] ?? "") }
      } compactLeading: {
        Image(systemName: "car.fill")
      } compactTrailing: {
        Text(v["eta"] ?? "")
      } minimal: {
        Image(systemName: "car.fill")
      }
    }
  }
}

// MARK: - Home-screen widget (NativeFlow.activities.updateWidget)

struct StatusEntry: TimelineEntry {
  let date: Date
  let values: [String: String]
}

struct StatusProvider: TimelineProvider {
  func placeholder(in context: Context) -> StatusEntry { StatusEntry(date: .now, values: ["status": "Offline"]) }

  func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
    // NativeFlow reloads this timeline whenever the app calls updateWidget.
    completion(Timeline(entries: [entry()], policy: .never))
  }

  private func entry() -> StatusEntry {
    let values = UserDefaults(suiteName: appGroup)?.dictionary(forKey: "driver") as? [String: String]
    return StatusEntry(date: .now, values: values ?? ["status": "Offline"])
  }
}

struct DriverStatusWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "DriverStatus", provider: StatusProvider()) { entry in
      VStack(alignment: .leading, spacing: 6) {
        Text("NativeFlow").font(.caption).foregroundStyle(.secondary)
        Text(entry.values["status"] ?? "Offline").font(.headline)
        Text(entry.values["detail"] ?? "").font(.caption)
      }
      .widgetBackground()
    }
    .configurationDisplayName("Driver status")
    .description("Updated by NativeFlow.activities.updateWidget.")
    .supportedFamilies([.systemSmall])
  }
}

extension View {
  /// iOS 17 requires a container background; earlier versions use padding.
  @ViewBuilder func widgetBackground() -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(.fill.tertiary, for: .widget)
    } else {
      padding()
    }
  }
}
