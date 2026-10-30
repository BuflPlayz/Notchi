import Foundation

/// Turns mediaremote-adapter `stream --micros` output into `NowPlayingInfo` values.
///
/// Each line is `{"type":"data","diff":Bool,"payload":{…}}`. A full payload replaces the state.
/// A diff merges only the changed keys, and `null` removes a key. An empty payload means nothing is
/// playing. Key names match the adapter's `src/adapter/keys.m` (v0.7.7).
struct AdapterStreamParser {
    enum Output: Equatable {
        case update(NowPlayingInfo?)
        case ignored
    }

    private var payload: [String: Any] = [:]

    mutating func consume(_ line: String) -> Output {
        guard
            let data = line.data(using: .utf8),
            let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            message["type"] as? String == "data",
            let incoming = message["payload"] as? [String: Any]
        else { return .ignored }

        if message["diff"] as? Bool == true {
            for (key, value) in incoming {
                payload[key] = value is NSNull ? nil : value
            }
        } else {
            payload = incoming
        }
        return .update(Self.info(from: payload))
    }

    static func info(from payload: [String: Any]) -> NowPlayingInfo? {
        guard let title = nonEmpty(payload["title"]) else { return nil }

        func seconds(_ key: String) -> TimeInterval? {
            (payload[key] as? NSNumber).map { $0.doubleValue / 1_000_000 }
        }

        return NowPlayingInfo(
            title: title,
            artist: nonEmpty(payload["artist"]),
            album: nonEmpty(payload["album"]),
            duration: seconds("durationMicros").flatMap { $0 > 0 ? $0 : nil },
            elapsed: seconds("elapsedTimeMicros") ?? 0,
            timestamp: seconds("timestampEpochMicros").map(Date.init(timeIntervalSince1970:)) ?? Date(),
            playbackRate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 0,
            isPlaying: (payload["playing"] as? NSNumber)?.boolValue ?? false,
            artworkData: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) },
            // Browser media comes from a helper process; the parent is the browser itself.
            sourceBundleIdentifier: nonEmpty(payload["parentApplicationBundleIdentifier"])
                ?? nonEmpty(payload["bundleIdentifier"])
        )
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
