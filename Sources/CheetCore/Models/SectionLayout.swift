import Foundation

/// How wide a section card is.
public enum CardWidth: Hashable, Sendable {
    /// One column of the automatic grid (full width for very wide tables).
    case auto
    /// Spans this many grid columns (clamped to the columns available).
    case columns(Int)
    /// A fraction of the content width, for free-form sizing.
    case fraction(Double)
}

extension CardWidth: Codable {
    private enum CodingKeys: String, CodingKey { case columns, fraction }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let n = try? c.decodeIfPresent(Int.self, forKey: .columns) {
            self = .columns(max(1, n))
        } else if let f = try? c.decodeIfPresent(Double.self, forKey: .fraction) {
            self = .fraction(min(1, max(0.05, f)))
        } else {
            self = .auto
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto: break
        case .columns(let n): try c.encode(n, forKey: .columns)
        case .fraction(let f): try c.encode(f, forKey: .fraction)
        }
    }
}

public enum CardFill: String, Codable, CaseIterable, Sendable {
    /// The cheet's normal card look.
    case standard
    /// No background at all.
    case none
    case solid
    case gradient
    /// Frosted glass over the overlay.
    case frosted

    public var label: String {
        switch self {
        case .standard: "Default"
        case .none: "None"
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .frosted: "Frosted"
        }
    }
}

public enum CardEffect: String, Codable, CaseIterable, Sendable {
    case none, glow, shadow, outline
    public var label: String { rawValue.capitalized }
}

/// Per-card visual overrides. `nil` values fall back to the cheet's appearance.
public struct CardStyle: Codable, Hashable, Sendable {
    public var fontSize: Double? = nil
    public var titleColor: RGBAColor? = nil
    public var textColor: RGBAColor? = nil
    public var fill: CardFill = .standard
    public var fillColor = RGBAColor(r: 0.33, g: 0.40, b: 0.88)
    public var fillColor2 = RGBAColor(r: 0.82, g: 0.36, b: 0.62)
    public var gradientAngle: Double = 135
    public var fillOpacity: Double = 0.35
    public var effect: CardEffect = .none
    /// `nil` = the card's title color / cheet accent.
    public var effectColor: RGBAColor? = nil
    public var cornerRadius: Double? = nil

    public init() {}

    public var isDefault: Bool { self == CardStyle() }

    private enum CodingKeys: String, CodingKey {
        case fontSize, titleColor, textColor, fill, fillColor, fillColor2, gradientAngle, fillOpacity, effect, effectColor, cornerRadius
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CardStyle()
        fontSize = c.optionalValue(.fontSize)
        titleColor = c.optionalValue(.titleColor)
        textColor = c.optionalValue(.textColor)
        fill = c.value(.fill, or: d.fill)
        fillColor = c.value(.fillColor, or: d.fillColor)
        fillColor2 = c.value(.fillColor2, or: d.fillColor2)
        gradientAngle = c.value(.gradientAngle, or: d.gradientAngle)
        fillOpacity = c.value(.fillOpacity, or: d.fillOpacity)
        effect = c.value(.effect, or: d.effect)
        effectColor = c.optionalValue(.effectColor)
        cornerRadius = c.optionalValue(.cornerRadius)
    }
}

/// Everything about how a section card is arranged and drawn in the overlay.
public struct SectionLayout: Codable, Hashable, Sendable {
    public var isHidden = false
    public var width: CardWidth = .auto
    /// Fixed height in points (content scrolls inside); `nil` = fit content.
    public var height: Double? = nil
    public var style = CardStyle()

    public init() {}

    public var isDefault: Bool { self == SectionLayout() }

    private enum CodingKeys: String, CodingKey { case isHidden, width, height, style }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isHidden = c.value(.isHidden, or: false)
        width = c.value(.width, or: .auto)
        height = c.optionalValue(.height)
        style = c.value(.style, or: CardStyle())
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value, falling back when the key is missing or malformed (forward/backward compatible files).
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    func optionalValue<T: Decodable>(_ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}
