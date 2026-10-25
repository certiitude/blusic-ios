import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var period = 7
    private var startDate: Date { Calendar.current.date(byAdding: .day, value: -(period - 1), to: Calendar.current.startOfDay(for: Date()))! }
    private var events: [ListeningEvent] { library.history.filter { $0.date >= startDate } }
    private var seconds: Double { events.reduce(0) { $0 + $1.seconds } }
    private var top: [(track: Track, seconds: Double, plays: Int)] {
        Dictionary(grouping: events, by: \.trackID).compactMap { id, values in
            guard let track = library.track(id) else { return nil }
            return (track, values.reduce(0) { $0 + $1.seconds }, values.filter { $0.seconds >= 30 }.count)
        }.sorted { $0.seconds > $1.seconds }
    }
    private var days: [(date: Date, seconds: Double)] {
        (0..<period).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: startDate)!
            return (date, events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.seconds })
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LA BANDE-SON DE TES JOURS").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(library.settings.color)
                    Text("Tes écoutes,\nen quelques notes.").font(.system(size: 33, weight: .bold, design: .rounded)).tracking(-1)
                }.padding(.top, 12)
                Picker("Période", selection: $period) {
                    Text("Aujourd’hui").tag(1); Text("7 jours").tag(7); Text("30 jours").tag(30)
                }.pickerStyle(.segmented)
                HStack(spacing: 12) {
                    stat(String(format: "%.1f h", seconds / 3600), label: "Temps d’écoute", symbol: "headphones")
                    stat("\(events.filter { $0.seconds >= 30 }.count)", label: "Écoutes", symbol: "waveform")
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("Un peu, beaucoup, à la folie.").font(.system(size: 15, weight: .semibold))
                    Chart(days, id: \.date) { day in
                        BarMark(x: .value("Jour", day.date, unit: .day), y: .value("Minutes", day.seconds / 60))
                            .foregroundStyle(LinearGradient(colors: [library.settings.color, library.settings.color.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                            .cornerRadius(5)
                    }
                    .chartYScale(domain: 0...max(1, (days.map { $0.seconds / 60 }.max() ?? 0) * 1.2))
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: period > 7 ? 5 : 1)) { _ in AxisValueLabel(format: .dateTime.day()) } }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Palette.line); AxisValueLabel() } }
                    .frame(height: 170).accessibilityLabel("Temps d’écoute quotidien en minutes")
                }.padding(20).surface()
                if let first = top.first {
                    HStack(spacing: 15) {
                        ArtworkView(track: first.track, size: 65, radius: 14)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TON TITRE DU MOMENT").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(library.settings.color)
                            Text(first.track.title).font(.headline).lineLimit(1)
                            Text(first.track.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(18).surface()
                }
                SectionHeading(title: "En boucle chez toi", subtitle: "Ton classement, basé sur le temps réellement écouté.")
                if top.isEmpty { EmptyState(symbol: "chart.bar", title: "Ton histoire commence", message: "Écoute tes premiers morceaux pour voir tes statistiques ici.") }
                ForEach(Array(top.prefix(20).enumerated()), id: \.element.track.id) { index, item in
                    VStack(alignment: .leading, spacing: 2) {
                        TrackRow(track: item.track, context: top.map(\.track), rank: index + 1)
                        Text("\(Int(item.seconds / 60)) min · \(item.plays) écoute\(item.plays > 1 ? "s" : "")")
                            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.leading, 98)
                    }
                }
                Text("Une écoute est comptée après 30 secondes. Le temps concerne le lecteur audio natif, pas les vidéos YouTube. Données conservées uniquement sur cet iPhone.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            }.pagePadding().padding(.bottom, 30)
        }.background(Palette.background).navigationTitle("Statistiques").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { dismiss() } } }
    }
    private func stat(_ value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(library.settings.color)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).surface()
    }
}
