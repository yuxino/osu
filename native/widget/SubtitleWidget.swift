import ActivityKit
import SwiftUI
import WidgetKit

@main struct SubtitleWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SubtitleActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        HStack { Text("Osu").fontWeight(.semibold); Spacer(); Text(context.isStale ? "等待更新" : context.state.status) }.font(.caption).foregroundStyle(.secondary)
        Text(context.state.translated).font(.headline).lineLimit(4)
        if context.state.showsOriginal && !context.state.original.isEmpty { Text(context.state.original).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
      }.padding(16).activityBackgroundTint(.black).activitySystemActionForegroundColor(.white).foregroundStyle(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Text("Osu").font(.caption.weight(.semibold)) }
        DynamicIslandExpandedRegion(.trailing) { Text(context.isStale ? "等待更新" : context.state.status).font(.caption).foregroundStyle(.secondary) }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(context.state.translated).font(.headline).lineLimit(3)
            if context.state.showsOriginal && !context.state.original.isEmpty { Text(context.state.original).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
        }
      } compactLeading: {
        Image(systemName: context.isStale ? "ellipsis" : "waveform").accessibilityLabel(context.isStale ? "等待更新" : context.state.status)
      } compactTrailing: {
        Text(context.isStale ? "等待更新" : context.state.translated).font(.caption2).lineLimit(1).frame(maxWidth: 90)
      } minimal: {
        Image(systemName: "waveform").accessibilityLabel("Osu 字幕")
      }.keylineTint(.white)
    }
  }
}
