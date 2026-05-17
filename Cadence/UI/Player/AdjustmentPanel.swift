import SwiftUI

struct AdjustmentPanel: View {
    let adjustment: UserMusicAdjustment
    @Binding var expanded: Bool
    let onToggleGenre: (String) -> Void
    let onClearGenres: () -> Void
    let onEnergyBias: (Int) -> Void
    let onFreeText: (String) -> Void

    @State private var freeTextValue: String = ""
    @State private var sliderPosition: Double = 0

    private let genres = ["jazz", "electronic", "pop", "rock", "ambient", "folk", "hip-hop", "classical"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { expanded.toggle() }) {
                HStack {
                    Text("ADJUST MUSIC")
                        .font(CadenceFont.labelMedium)
                        .foregroundStyle(expanded ? CadenceColor.text : CadenceColor.textSecondary)
                    Spacer()
                    let hints = buildAdjustmentHints(adjustment).joined(separator: " · ")
                    if !hints.isEmpty {
                        Text(hints).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.orange)
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(CadenceColor.blue)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Spacer().frame(height: 16)
                Text("GENRE")
                    .font(CadenceFont.labelMedium)
                    .foregroundStyle(CadenceColor.textMute)
                Spacer().frame(height: 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        genrePill("Auto", selected: adjustment.genreOverrides.isEmpty) { onClearGenres() }
                        ForEach(genres, id: \.self) { genre in
                            genrePill(genre.capitalized, selected: adjustment.genreOverrides.contains(genre)) {
                                onToggleGenre(genre)
                            }
                        }
                    }
                }
                Spacer().frame(height: 18)
                Text("ENERGY")
                    .font(CadenceFont.labelMedium)
                    .foregroundStyle(CadenceColor.textMute)
                Spacer().frame(height: 10)
                HStack(spacing: 12) {
                    Text("Calmer").font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textMute)
                    Slider(value: $sliderPosition, in: -2...2, step: 1) { editing in
                        if !editing { onEnergyBias(Int(sliderPosition)) }
                    }
                    .tint(CadenceColor.blue)
                    Text("More").font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textMute)
                }
                Spacer().frame(height: 14)
                HStack(spacing: 10) {
                    TextField("Try: 'more cinematic', 'add piano'…", text: $freeTextValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit(submit)
                    Button(action: submit) {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(freeTextValue.isEmpty ? CadenceColor.blue.opacity(0.35) : CadenceColor.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(freeTextValue.isEmpty)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.02))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1.5))
                )
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(expanded ? Color(hex: 0x0E1117).opacity(0.92) : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .onAppear { sliderPosition = Double(adjustment.energyBias) }
    }

    private func submit() {
        if !freeTextValue.isEmpty {
            onFreeText(freeTextValue)
            freeTextValue = ""
        }
    }

    private func genrePill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(CadenceFont.titleSmall)
                .foregroundStyle(selected ? .white : CadenceColor.text)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selected ? CadenceColor.blue : .clear)
                        .overlay(Capsule().stroke(selected ? CadenceColor.blue : Color.white.opacity(0.1), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

func buildAdjustmentHints(_ adjustment: UserMusicAdjustment) -> [String] {
    var hints: [String] = []
    hints.append(contentsOf: adjustment.genreOverrides.map { $0.uppercased() })
    if adjustment.energyBias >= 1 { hints.append("+ENERGY") }
    if adjustment.energyBias <= -1 { hints.append("-ENERGY") }
    if adjustment.freeText != nil { hints.append("CUSTOM") }
    return hints
}
