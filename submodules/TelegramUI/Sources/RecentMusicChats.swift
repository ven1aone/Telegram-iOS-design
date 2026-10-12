import Foundation
import TelegramCore

/// The chats music was most recently played from, newest first, per account. Fed whenever music
/// starts playing from a chat (`TelegramRootController`), read by the music player's chat chips.
/// Device-local and small, so it lives in `UserDefaults`.
enum RecentMusicChats {
    static let maxCount = 12
    
    private static func key(accountPeerId: EnginePeer.Id) -> String {
        return "telegram.recentMusicChats.\(accountPeerId.toInt64())"
    }
    
    static func get(accountPeerId: EnginePeer.Id) -> [EnginePeer.Id] {
        let values = UserDefaults.standard.array(forKey: self.key(accountPeerId: accountPeerId)) as? [Int64] ?? []
        return values.map(EnginePeer.Id.init)
    }
    
    static func note(peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) {
        var peerIds = self.get(accountPeerId: accountPeerId)
        if peerIds.first == peerId {
            return
        }
        peerIds.removeAll(where: { $0 == peerId })
        peerIds.insert(peerId, at: 0)
        if peerIds.count > self.maxCount {
            peerIds.removeLast(peerIds.count - self.maxCount)
        }
        UserDefaults.standard.set(peerIds.map { $0.toInt64() }, forKey: self.key(accountPeerId: accountPeerId))
    }
}
