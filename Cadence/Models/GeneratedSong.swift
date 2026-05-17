import Foundation

struct GeneratedSong: Identifiable, Equatable, Sendable {
    let id: Int64
    let params: SongParams
    let mentalState: MentalState?
    let scene: Scene?
    let generatedAt: Int64
}
