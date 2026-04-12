import Foundation

struct CobaltErrorResponse: Decodable {
    let status: String?
    let error: CobaltErrorPayload?
    let service: String?
    let limit: String?

    enum CodingKeys: String, CodingKey {
        case status
        case error
        case service
        case limit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        error = try container.decodeIfPresent(CobaltErrorPayload.self, forKey: .error)
        service = Self.decodeFlexibleString(from: container, forKey: .service)
        limit = Self.decodeFlexibleString(from: container, forKey: .limit)
    }

    fileprivate static func decodeFlexibleString<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            if value.rounded() == value {
                return String(Int(value))
            }

            return String(value)
        }

        return nil
    }
}

struct CobaltErrorPayload: Decodable {
    let code: String?
    let service: String?
    let limit: String?

    enum CodingKeys: String, CodingKey {
        case code
        case service
        case limit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        service = CobaltErrorResponse.decodeFlexibleString(from: container, forKey: .service)
        limit = CobaltErrorResponse.decodeFlexibleString(from: container, forKey: .limit)
    }
}

enum CobaltErrorTranslator {
    private static let genericMessage = "something went wrong and i couldn't get anything for you, try again in a few seconds. if the issue sticks, please report it!"

    private static let messages: [String: String] = [
        "auth.jwt.missing": "couldn't authenticate with the processing instance because the access token is missing. try again in a few seconds or reload the page!",
        "auth.jwt.invalid": "couldn't authenticate with the processing instance because the access token is invalid. try again in a few seconds or reload the page!",
        "auth.turnstile.missing": "couldn't authenticate with the processing instance because the captcha solution is missing. try again in a few seconds or reload the page!",
        "auth.turnstile.invalid": "couldn't authenticate with the processing instance because the captcha solution is invalid. try again in a few seconds or reload the page!",
        "auth.key.missing": "an access key is required to use this processing instance but it's missing. add it in instance settings!",
        "auth.key.not_api_key": "an access key is required to use this processing instance but it's missing. add it in instance settings!",
        "auth.key.invalid": "the access key is invalid. reset it in instance settings and use a proper one!",
        "auth.key.not_found": "the access key you used couldn't be found. are you sure this instance has your key?",
        "auth.key.invalid_ip": "your ip address couldn't be parsed. something went very wrong. report this issue!",
        "auth.key.ip_not_allowed": "your ip address is not allowed to use this access key. use a different instance or network!",
        "auth.key.ua_not_allowed": "your user agent is not allowed to use this access key. use a different client or device!",
        "unreachable": "couldn't connect to the processing instance. check your internet connection and try again!",
        "timed_out": "the processing instance took too long to respond. it may be overwhelmed at the moment, try again in a few seconds!",
        "rate_exceeded": "you're making too many requests. try again in {{ limit }} seconds.",
        "capacity": "cobalt is at capacity and can't process your request at the moment. try again in a few seconds!",
        "generic": genericMessage,
        "unknown_response": "couldn't read the response from the processing instance. this is probably caused by the web app being out of date. reload the app and try again!",
        "invalid_body": "couldn't send the request to the processing instance. this is probably caused by the web app being out of date. reload the app and try again!",
        "service.unsupported": "this service is not supported yet. have you pasted the right link?",
        "service.disabled": "this service is generally supported by cobalt, but it's disabled on this processing instance. try a link from another service!",
        "service.audio_not_supported": "this service doesn't support audio extraction. try a link from another service!",
        "link.invalid": "your link is invalid or this service is not supported yet. have you pasted the right link?",
        "link.unsupported": "{{ service }} is supported, but i couldn't recognize your link. have you pasted the right one?",
        "fetch.fail": "something went wrong when fetching info from {{ service }} and i couldn't get anything for you. if this issue sticks, please report it!",
        "fetch.critical": "the {{ service }} module returned an error that i don't recognize. try again in a few seconds, but if this issue sticks, please report it!",
        "fetch.critical.core": "one of the core modules returned an error that i don't recognize. try again in a few seconds, but if this issue sticks, please report it!",
        "fetch.empty": "couldn't find any media that i could download for you. are you sure you pasted the right link?",
        "fetch.rate": "the processing instance got rate limited by {{ service }}. try again in a few seconds!",
        "fetch.short_link": "couldn't get info from the short link. are you sure it works? if it does and you still get this error, please report this issue!",
        "content.too_long": "media you requested is too long. the duration limit on this instance is {{ limit }} minutes. try something shorter instead!",
        "content.video.unavailable": "i can't access this video. it may be restricted on {{ service }}'s side. try a different link!",
        "content.video.live": "this video is currently live, so i can't download it yet. wait for the live stream to finish and try again!",
        "content.video.private": "this video is private, so i can't access it. change its visibility or try another one!",
        "content.video.age": "this video is age-restricted, so i can't access it anonymously. try again or try a different link!",
        "content.video.region": "this video is region locked, and the processing instance is in a different location. try a different link!",
        "content.region": "this content is region locked, and the processing instance is in a different location. try a different link!",
        "content.paid": "this content requires purchase. cobalt can't download paid content. try a different link!",
        "content.post.unavailable": "couldn't find anything about this post. its visibility may be limited or it may not exist. make sure your link works and try again in a few seconds!",
        "content.post.private": "couldn't get anything about this post because it's from a private account. try a different link!",
        "content.post.age": "this post is age-restricted, so i can't access it anonymously. try again or try a different link!",
        "youtube.no_matching_format": "youtube didn't return any acceptable formats. cobalt may not support them or they're re-encoding on youtube's side. try again a bit later, but if this issue sticks, please report it!",
        "youtube.decipher": "youtube updated its decipher algorithm and i couldn't extract the info about the video. try again in a few seconds, but if this issue sticks, please report it!",
        "youtube.login": "couldn't get this video because youtube asked the processing instance to prove that it's not a bot. try again in a few seconds, but if it still doesn't work, please report this issue!",
        "youtube.token_expired": "couldn't get this video because the youtube token expired and wasn't refreshed. try again in a few seconds, but if it still doesn't work, please report this issue!",
        "youtube.no_hls_streams": "couldn't find any matching HLS streams for this video. try downloading it without HLS!",
        "youtube.api_error": "youtube updated something about its api and i couldn't get any info about this video. try again in a few seconds, but if this issue sticks, please report it!",
        "youtube.disabled_main_instance": "youtube downloading is disabled on the main instance due to restrictions from youtube's side and infinite maintenance cost at scale.\n\nwe apologize for the inconvenience and encourage you to host your own API instance for this.",
        "youtube.drm": "this youtube video is protected by widevine DRM, so i can't download it. try a different link!",
        "youtube.no_session_tokens": "couldn't get required session tokens for youtube. this may be caused by a restriction on youtube's side. try again in a few seconds, but if this issue sticks, please report it!"
    ]

    static func decodeResponse(from data: Data) -> CobaltErrorResponse? {
        try? JSONDecoder().decode(CobaltErrorResponse.self, from: data)
    }

    static var fallbackMessage: String {
        genericMessage
    }

    static func message(from response: CobaltErrorResponse) -> String {
        guard let normalizedCode = normalizeCode(response.error?.code) else {
            return genericMessage
        }

        guard let template = messages[normalizedCode] else {
            return genericMessage
        }

        let service = response.error?.service ?? response.service
        let limit = response.error?.limit ?? response.limit

        if template.contains("{{ service }}"), service == nil {
            return fallbackMessage(for: normalizedCode) ?? genericMessage
        }

        if template.contains("{{ limit }}"), limit == nil {
            return fallbackMessage(for: normalizedCode) ?? genericMessage
        }

        return template
            .replacingOccurrences(of: "{{ service }}", with: service ?? "this service")
            .replacingOccurrences(of: "{{ limit }}", with: limit ?? "a few")
    }

    private static func normalizeCode(_ code: String?) -> String? {
        guard let code, !code.isEmpty else {
            return nil
        }

        if code.hasPrefix("error.api.") {
            return String(code.dropFirst("error.api.".count))
        }

        if code.hasPrefix("error.") {
            return String(code.dropFirst("error.".count))
        }

        return code
    }

    private static func fallbackMessage(for normalizedCode: String) -> String? {
        switch normalizedCode {
        case "rate_exceeded":
            return "you're making too many requests. try again in a few seconds."
        case "link.unsupported":
            return "this service is supported, but i couldn't recognize your link. have you pasted the right one?"
        case "fetch.fail":
            return "something went wrong when fetching info from this service and i couldn't get anything for you. if this issue sticks, please report it!"
        case "fetch.critical":
            return "the service module returned an error that i don't recognize. try again in a few seconds, but if this issue sticks, please report it!"
        case "fetch.rate":
            return "the processing instance got rate limited by this service. try again in a few seconds!"
        case "content.too_long":
            return "media you requested is too long for this instance. try something shorter instead!"
        case "content.video.unavailable":
            return "i can't access this video. it may be restricted on the service's side. try a different link!"
        default:
            return nil
        }
    }
}
