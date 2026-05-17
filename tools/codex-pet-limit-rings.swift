import AppKit
import Darwin
import Foundation
import SQLite3

struct LimitBucket {
    var usedPercent: Double
    var windowMinutes: Double?
    var resetAt: TimeInterval?

    var remainingPercent: Double {
        min(max(100.0 - usedPercent, 0.0), 100.0)
    }
}

struct LimitState {
    var planType: String?
    var primary: LimitBucket?
    var secondary: LimitBucket?
    var additional: [(name: String, bucket: LimitBucket)]
    var observedAt: Date
    var source: String

    static let empty = LimitState(planType: nil, primary: nil, secondary: nil, additional: [], observedAt: Date(), source: "none")
}

private let limitStatePollInterval: TimeInterval = 20.0
private let petFrameFallbackPollInterval: TimeInterval = 2.0
private let petFrameStateDebounceInterval: TimeInterval = 0.035
private let ringPanelPadding: CGFloat = 38.0
private let readoutBottomExtension: CGFloat = 44.0
private let ringsVisibleDefaultsKey = "CodexPetLimitRings.ringsVisible"
private let ringColorPresetDefaultsPrefix = "CodexPetLimitRings.colorPreset."
private let outerRingColorPresetDefaultsPrefix = "CodexPetLimitRings.outerColorPreset."
private let innerRingColorPresetDefaultsPrefix = "CodexPetLimitRings.innerColorPreset."
private let outerRingCustomColorDefaultsPrefix = "CodexPetLimitRings.outerCustomColor."
private let innerRingCustomColorDefaultsPrefix = "CodexPetLimitRings.innerCustomColor."
private let outerRingOpacityPresetDefaultsPrefix = "CodexPetLimitRings.outerOpacityPreset."
private let innerRingOpacityPresetDefaultsPrefix = "CodexPetLimitRings.innerOpacityPreset."
private let defaultRingColorPresetID = "default"
private let defaultRingOpacityPresetID = "100"
private let defaultAvatarColorKey = "__default__"
private let liveUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
private let codexSettingsURL = URL(string: "codex://settings")!

struct RingColorPalette {
    var primary: NSColor
    var secondary: NSColor

    static let `default` = RingColorPalette(
        primary: NSColor(calibratedRed: 0.24, green: 0.92, blue: 0.74, alpha: 0.96),
        secondary: NSColor(calibratedRed: 0.36, green: 0.70, blue: 1.00, alpha: 0.90)
    )
}

struct RingColorPreset {
    var id: String
    var title: String
    var palette: RingColorPalette

    static let all: [RingColorPreset] = [
        RingColorPreset(id: defaultRingColorPresetID, title: "Default", palette: .default),
        RingColorPreset(
            id: "sakura",
            title: "Sakura",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 1.00, green: 0.48, blue: 0.70, alpha: 0.96),
                secondary: NSColor(calibratedRed: 0.78, green: 0.62, blue: 1.00, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "amber",
            title: "Amber",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 1.00, green: 0.67, blue: 0.24, alpha: 0.96),
                secondary: NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.34, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "purple",
            title: "Purple",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 0.72, green: 0.48, blue: 1.00, alpha: 0.96),
                secondary: NSColor(calibratedRed: 0.82, green: 0.58, blue: 1.00, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "brown",
            title: "Brown",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 0.78, green: 0.52, blue: 0.30, alpha: 0.96),
                secondary: NSColor(calibratedRed: 0.68, green: 0.48, blue: 0.32, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "emerald",
            title: "Emerald",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 0.22, green: 0.95, blue: 0.46, alpha: 0.96),
                secondary: NSColor(calibratedRed: 0.38, green: 0.88, blue: 0.62, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "aqua",
            title: "Aqua",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 0.14, green: 0.86, blue: 1.00, alpha: 0.96),
                secondary: NSColor(calibratedRed: 0.50, green: 0.96, blue: 1.00, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "ruby",
            title: "Ruby",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 1.00, green: 0.24, blue: 0.42, alpha: 0.96),
                secondary: NSColor(calibratedRed: 1.00, green: 0.48, blue: 0.56, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "lime",
            title: "Lime",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 0.70, green: 1.00, blue: 0.24, alpha: 0.96),
                secondary: NSColor(calibratedRed: 0.86, green: 1.00, blue: 0.40, alpha: 0.92)
            )
        ),
        RingColorPreset(
            id: "graphite",
            title: "Graphite",
            palette: RingColorPalette(
                primary: NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.88, alpha: 0.96),
                secondary: NSColor(calibratedRed: 0.54, green: 0.60, blue: 0.68, alpha: 0.92)
            )
        )
    ]

    static func preset(for id: String?) -> RingColorPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

struct RingOpacitySettings {
    var primary: CGFloat
    var secondary: CGFloat

    static let `default` = RingOpacitySettings(primary: 1.0, secondary: 1.0)
}

struct RingOpacityPreset {
    var id: String
    var title: String
    var opacity: CGFloat

    static let all: [RingOpacityPreset] = [
        RingOpacityPreset(id: defaultRingOpacityPresetID, title: "100%", opacity: 1.00),
        RingOpacityPreset(id: "85", title: "85%", opacity: 0.85),
        RingOpacityPreset(id: "70", title: "70%", opacity: 0.70),
        RingOpacityPreset(id: "55", title: "55%", opacity: 0.55),
        RingOpacityPreset(id: "40", title: "40%", opacity: 0.40)
    ]

    static func preset(for id: String?) -> RingOpacityPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

private struct EventPayload: Decodable {
    var type: String
    var plan_type: String?
    var rate_limits: RatePayload?
    var additional_rate_limits: [String: RatePayload]?
}

private struct AuthPayload: Decodable {
    var tokens: AuthTokens?
}

private struct AuthTokens: Decodable {
    var access_token: String?
}

private struct UsagePayload: Decodable {
    var plan_type: String?
    var rate_limit: RatePayload?
    var additional_rate_limits: [AdditionalUsagePayload]?
}

private struct AdditionalUsagePayload: Decodable {
    var limit_name: String?
    var metered_feature: String?
    var rate_limit: RatePayload?
}

private struct RatePayload: Decodable {
    var primary: BucketPayload?
    var secondary: BucketPayload?
    var primary_window: BucketPayload?
    var secondary_window: BucketPayload?
}

private struct BucketPayload: Decodable {
    var used_percent: Double?
    var window_minutes: Double?
    var limit_window_seconds: Double?
    var reset_at: Double?

    func toBucket() -> LimitBucket? {
        guard let used = used_percent else { return nil }
        let minutes = window_minutes ?? limit_window_seconds.map { $0 / 60.0 }
        return LimitBucket(usedPercent: used, windowMinutes: minutes, resetAt: reset_at)
    }
}

struct LimitRingsConfig {
    var codexHome: URL
    var globalStatePath: URL
    var logsPath: URL
    var authPath: URL
    var previewPath: URL?
    var fallbackSize: CGFloat = 220
}

final class LimitStateReader {
    private let logsPath: URL
    private let authPath: URL

    init(logsPath: URL, authPath: URL) {
        self.logsPath = logsPath
        self.authPath = authPath
    }

    func readLatest() -> LimitState {
        if let liveState = readLiveUsage() {
            return liveState
        }
        return readLatestLog()
    }

    private func readLiveUsage() -> LimitState? {
        guard let token = readAccessToken() else {
            return nil
        }

        var request = URLRequest(url: liveUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: URLResponse?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            resultData = data
            resultResponse = response
            semaphore.signal()
        }.resume()

        guard semaphore.wait(timeout: .now() + 7.0) == .success,
              let http = resultResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let data = resultData,
              let payload = try? JSONDecoder().decode(UsagePayload.self, from: data) else {
            return nil
        }

        let primary = (payload.rate_limit?.primary ?? payload.rate_limit?.primary_window)?.toBucket()
        let secondary = (payload.rate_limit?.secondary ?? payload.rate_limit?.secondary_window)?.toBucket()
        let additional = (payload.additional_rate_limits ?? [])
            .compactMap { item -> (String, LimitBucket)? in
                guard let bucket = (item.rate_limit?.primary ?? item.rate_limit?.primary_window ?? item.rate_limit?.secondary ?? item.rate_limit?.secondary_window)?.toBucket() else {
                    return nil
                }
                return (item.limit_name ?? item.metered_feature ?? "Additional", bucket)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

        return LimitState(planType: payload.plan_type, primary: primary, secondary: secondary, additional: additional, observedAt: Date(), source: "live")
    }

    private func readAccessToken() -> String? {
        guard let data = try? Data(contentsOf: authPath),
              let payload = try? JSONDecoder().decode(AuthPayload.self, from: data),
              let token = payload.tokens?.access_token,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private func readLatestLog() -> LimitState {
        guard FileManager.default.fileExists(atPath: logsPath.path) else {
            return .empty
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(logsPath.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard openResult == SQLITE_OK, let db else {
            return .empty
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT feedback_log_body
        FROM logs
        WHERE feedback_log_body LIKE '%"type":"codex.rate_limits"%'
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cText = sqlite3_column_text(statement, 0) else {
            return .empty
        }

        let body = String(cString: cText)
        guard let json = extractRateLimitJSON(from: body),
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(EventPayload.self, from: data) else {
            return .empty
        }

        let primary = (payload.rate_limits?.primary ?? payload.rate_limits?.primary_window)?.toBucket()
        let secondary = (payload.rate_limits?.secondary ?? payload.rate_limits?.secondary_window)?.toBucket()
        let additional = (payload.additional_rate_limits ?? [:])
            .compactMap { name, payload -> (String, LimitBucket)? in
                guard let bucket = (payload.primary ?? payload.primary_window ?? payload.secondary ?? payload.secondary_window)?.toBucket() else {
                    return nil
                }
                return (name, bucket)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

        return LimitState(planType: payload.plan_type, primary: primary, secondary: secondary, additional: additional, observedAt: Date(), source: "log")
    }

    private func extractRateLimitJSON(from body: String) -> String? {
        guard let start = body.range(of: "{\"type\":\"codex.rate_limits\"")?.lowerBound else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaping = false
        var endIndex: String.Index?
        var index = start

        while index < body.endIndex {
            let char = body[index]
            if inString {
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = body.index(after: index)
                        break
                    }
                }
            }
            index = body.index(after: index)
        }

        guard let endIndex else { return nil }
        return String(body[start..<endIndex])
    }
}

final class PetFrameReader {
    private let globalStatePath: URL

    init(globalStatePath: URL) {
        self.globalStatePath = globalStatePath
    }

    func readPetFrameTopLeft() -> CGRect? {
        guard let data = try? Data(contentsOf: globalStatePath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              isAvatarOverlayOpen(root),
              let bounds = root["electron-avatar-overlay-bounds"] as? [String: Any],
              let x = number(bounds["x"]),
              let y = number(bounds["y"]),
              let mascot = bounds["mascot"] as? [String: Any],
              let left = number(mascot["left"]),
              let top = number(mascot["top"]),
              let width = number(mascot["width"]),
              let height = number(mascot["height"]) else {
            return nil
        }

        return CGRect(x: x + left, y: y + top, width: width, height: height)
    }

    func readSelectedAvatarID() -> String? {
        guard let data = try? Data(contentsOf: globalStatePath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atomState = root["electron-persisted-atom-state"] as? [String: Any],
              let avatarID = atomState["selected-avatar-id"] as? String,
              !avatarID.isEmpty else {
            return nil
        }
        return avatarID
    }

    private func isAvatarOverlayOpen(_ root: [String: Any]) -> Bool {
        if let isOpen = root["electron-avatar-overlay-open"] as? Bool {
            return isOpen
        }
        if let isOpen = root["electron-avatar-overlay-open"] as? NSNumber {
            return isOpen.boolValue
        }
        return true
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let value = value as? NSNumber {
            return CGFloat(truncating: value)
        }
        if let value = value as? Double {
            return CGFloat(value)
        }
        if let value = value as? Int {
            return CGFloat(value)
        }
        return nil
    }
}

struct LimitRingRenderer {
    var state: LimitState
    var phase: Double
    var showsReadout: Bool = false
    var colorPalette: RingColorPalette = .default
    var opacitySettings: RingOpacitySettings = .default
    var ringCenter: CGPoint? = nil

    func draw(in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        context.clear(rect)

        let center = ringCenter ?? CGPoint(x: rect.midX, y: rect.midY)
        let minSide = min(rect.width, rect.height)
        let urgency = max(urgency(for: state.primary), urgency(for: state.secondary))
        let breathe = CGFloat((sin(phase * 2.0 * .pi) + 1.0) * 0.5)
        let pulse = CGFloat(1.0 + urgency * 0.025 * breathe)
        let outerRadius = (minSide * 0.5 - 16.0) * pulse
        let innerRadius = outerRadius - 13.0

        drawHalo(context, center: center, radius: outerRadius, urgency: CGFloat(urgency), breathe: breathe)
        drawTicks(context, center: center, radius: outerRadius + 5.0)

        if let primary = state.primary {
            drawRing(
                context,
                center: center,
                radius: outerRadius,
                lineWidth: 7.0,
                bucket: primary,
                color: color(forRemaining: primary.remainingPercent, role: .primary),
                trackAlpha: 0.20,
                opacity: opacity(for: .primary),
                phase: phase
            )
        } else {
            drawMissingRing(context, center: center, radius: outerRadius, lineWidth: 7.0, opacity: opacity(for: .primary))
        }

        if let secondary = state.secondary {
            drawRing(
                context,
                center: center,
                radius: innerRadius,
                lineWidth: 4.5,
                bucket: secondary,
                color: color(forRemaining: secondary.remainingPercent, role: .secondary),
                trackAlpha: 0.14,
                opacity: opacity(for: .secondary),
                phase: phase + 0.18
            )
        }

        drawModelLimitDots(context, center: center, radius: outerRadius + 11.0, state: state)
        if showsReadout {
            drawLimitReadouts(context, bounds: rect)
        }
        context.restoreGState()
    }

    private enum RingRole {
        case primary
        case secondary
    }

    private struct LimitHUDRow {
        var label: String
        var remainingText: String
        var resetText: String
        var color: NSColor
    }

    private func urgency(for bucket: LimitBucket?) -> Double {
        guard let bucket else { return 0.0 }
        return min(max((45.0 - bucket.remainingPercent) / 45.0, 0.0), 1.0)
    }

    private func drawHalo(_ context: CGContext, center: CGPoint, radius: CGFloat, urgency: CGFloat, breathe: CGFloat) {
        context.saveGState()
        let color = NSColor(calibratedRed: 0.23 + urgency * 0.55, green: 0.85 - urgency * 0.30, blue: 0.78 - urgency * 0.48, alpha: 0.22 + urgency * 0.16)
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 14.0 + urgency * breathe * 5.0, color: color.withAlphaComponent(0.55).cgColor)
        context.setStrokeColor(color.withAlphaComponent(0.20).cgColor)
        context.setLineWidth(8.0)
        context.addArc(center: center, radius: radius + 3.0, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()
        context.setShadow(offset: .zero, blur: 0.0, color: nil)
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.045).cgColor)
        context.setLineWidth(1.0)
        context.addArc(center: center, radius: radius + 13.0, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()
        context.restoreGState()
    }

    private func drawTicks(_ context: CGContext, center: CGPoint, radius: CGFloat) {
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor)
        context.setLineWidth(1.2)
        context.setLineCap(.round)
        for i in 0..<24 {
            guard i % 2 == 0 else { continue }
            let angle = -CGFloat.pi / 2.0 + CGFloat(i) / 24.0 * CGFloat.pi * 2.0
            let inner = radius - 1.5
            let outer = radius + 2.5
            context.move(to: point(center: center, radius: inner, angle: angle))
            context.addLine(to: point(center: center, radius: outer, angle: angle))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawRing(
        _ context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        bucket: LimitBucket,
        color: NSColor,
        trackAlpha: CGFloat,
        opacity: CGFloat,
        phase: Double
    ) {
        let opacity = clampOpacity(opacity)
        let start = -CGFloat.pi / 2.0
        let remaining = CGFloat(bucket.remainingPercent / 100.0)
        let end = start + max(remaining, 0.018) * CGFloat.pi * 2.0

        context.saveGState()
        context.setLineCap(.round)
        context.setLineWidth(lineWidth)
        context.setStrokeColor(NSColor(calibratedWhite: 0.0, alpha: 0.22 * opacity).cgColor)
        context.addArc(center: center, radius: radius + 1.0, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()

        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: trackAlpha * opacity).cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()

        context.setShadow(offset: .zero, blur: 10.0, color: color.withAlphaComponent(0.42 * opacity).cgColor)
        context.setStrokeColor(color.withAlphaComponent(0.30 * opacity).cgColor)
        context.setLineWidth(lineWidth + 6.0)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()

        context.setShadow(offset: .zero, blur: 4.0, color: color.withAlphaComponent(0.52 * opacity).cgColor)
        context.setStrokeColor(color.withAlphaComponent(color.alphaComponent * opacity).cgColor)
        context.setLineWidth(lineWidth)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()

        let glintAngle = start + CGFloat(phase.truncatingRemainder(dividingBy: 1.0)) * CGFloat.pi * 2.0
        let glint = point(center: center, radius: radius, angle: glintAngle)
        context.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.38 * opacity).cgColor)
        context.fillEllipse(in: CGRect(x: glint.x - 1.8, y: glint.y - 1.8, width: 3.6, height: 3.6))
        context.restoreGState()
    }

    private func drawMissingRing(_ context: CGContext, center: CGPoint, radius: CGFloat, lineWidth: CGFloat, opacity: CGFloat) {
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.16 * clampOpacity(opacity)).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 1.74, clockwise: false)
        context.strokePath()
        context.restoreGState()
    }

    private func drawLimitReadouts(_ context: CGContext, bounds: CGRect) {
        let rows = limitHUDRows()
        if rows.isEmpty {
            drawEmptyLimitHUD(context, bounds: bounds)
            return
        }

        drawLimitHUD(context, rows: rows, bounds: bounds)
    }

    private func limitHUDRows() -> [LimitHUDRow] {
        var rows: [LimitHUDRow] = []
        if let primary = state.primary {
            rows.append(makeHUDRow(bucket: primary, role: .primary, fallbackLabel: "5h"))
        }
        if let secondary = state.secondary {
            rows.append(makeHUDRow(bucket: secondary, role: .secondary, fallbackLabel: "Week"))
        }
        return rows
    }

    private func makeHUDRow(bucket: LimitBucket, role: RingRole, fallbackLabel: String) -> LimitHUDRow {
        LimitHUDRow(
            label: limitLabel(for: bucket, fallback: fallbackLabel),
            remainingText: "\(formatPercent(bucket.remainingPercent)) left",
            resetText: formatResetText(for: bucket),
            color: color(forRemaining: bucket.remainingPercent, role: role)
        )
    }

    private func drawLimitHUD(_ context: CGContext, rows: [LimitHUDRow], bounds: CGRect) {
        let rect = hudRect(rowCount: rows.count, bounds: bounds)
        context.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: 8.0, cornerHeight: 8.0, transform: nil)
        context.setShadow(offset: .zero, blur: 10.0, color: NSColor(calibratedWhite: 0.0, alpha: 0.38).cgColor)
        context.setFillColor(NSColor(calibratedWhite: 0.055, alpha: 0.84).cgColor)
        context.addPath(path)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0.0, color: nil)
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        let paddingX: CGFloat = 9.0
        let rowHeight: CGFloat = 20.0
        let rowGap: CGFloat = 4.0
        let availableWidth = rect.width - paddingX * 2.0 - 8.0
        let textWidth = availableWidth - 8.0
        let labelWidth: CGFloat = 30.0
        let contentGap: CGFloat = 5.0
        let contentFontSize = hudContentFontSize(for: rows, maxWidth: textWidth - labelWidth - contentGap)

        for (index, row) in rows.enumerated() {
            let rowY = rect.maxY - 8.0 - rowHeight - CGFloat(index) * (rowHeight + rowGap)
            let rowRect = CGRect(x: rect.minX + paddingX, y: rowY, width: availableWidth, height: rowHeight)
            let accentRect = CGRect(x: rowRect.minX, y: rowRect.midY - 4.2, width: 3.0, height: 8.4)
            context.setFillColor(row.color.withAlphaComponent(0.95).cgColor)
            context.fillEllipse(in: accentRect)

            let textRect = CGRect(x: rowRect.minX + 8.0, y: rowRect.minY + 1.0, width: rowRect.width - 8.0, height: rowHeight)
            drawHUDRow(row, in: textRect, labelWidth: labelWidth, contentGap: contentGap, contentFontSize: contentFontSize)
        }

        context.restoreGState()
    }

    private func drawEmptyLimitHUD(_ context: CGContext, bounds: CGRect) {
        let text = "Waiting for limit data"
        let rect = clampHUDRect(CGRect(x: bounds.midX - 76.0, y: bounds.minY + 10.0, width: 152.0, height: 32.0), bounds: bounds)

        context.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: 8.0, cornerHeight: 8.0, transform: nil)
        context.setShadow(offset: .zero, blur: 10.0, color: NSColor(calibratedWhite: 0.0, alpha: 0.34).cgColor)
        context.setFillColor(NSColor(calibratedWhite: 0.055, alpha: 0.82).cgColor)
        context.addPath(path)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0.0, color: nil)
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()
        drawHUDText(text, in: rect.insetBy(dx: 10.0, dy: 7.0), fontSize: 9.4, weight: .medium, color: NSColor(calibratedWhite: 1.0, alpha: 0.76), alignment: .center)
        context.restoreGState()
    }

    private func hudRect(rowCount: Int, bounds: CGRect) -> CGRect {
        let width = min(max(bounds.width - 8.0, 148.0), 218.0)
        let height = 18.0 + CGFloat(rowCount) * 20.0 + CGFloat(max(rowCount - 1, 0)) * 4.0
        let candidate = CGRect(x: bounds.midX - width / 2.0, y: bounds.minY + 8.0, width: width, height: height)
        return clampHUDRect(candidate, bounds: bounds)
    }

    private func clampHUDRect(_ rect: CGRect, bounds: CGRect) -> CGRect {
        var clamped = rect
        let inset = bounds.insetBy(dx: 4.0, dy: 4.0)
        clamped.size.width = min(clamped.width, inset.width)
        clamped.size.height = min(clamped.height, inset.height)
        clamped.origin.x = min(max(clamped.minX, inset.minX), inset.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.minY, inset.minY), inset.maxY - clamped.height)
        return clamped
    }

    private func drawHUDRow(_ row: LimitHUDRow, in rect: CGRect, labelWidth: CGFloat, contentGap: CGFloat, contentFontSize: CGFloat) {
        let label = hudSegment(row.label, fontSize: 10.4, weight: .bold, color: row.color)
        let labelSize = label.size()
        label.draw(at: CGPoint(x: rect.minX, y: rect.midY - labelSize.height / 2.0 + 0.5))

        let content = NSMutableAttributedString()
        content.append(hudSegment(row.remainingText, fontSize: contentFontSize, weight: .semibold, color: NSColor(calibratedWhite: 1.0, alpha: 0.99)))
        content.append(hudSegment(" ", fontSize: contentFontSize, weight: .medium, color: NSColor(calibratedWhite: 1.0, alpha: 0.90)))
        content.append(hudSegment(row.resetText, fontSize: contentFontSize, weight: .semibold, color: NSColor(calibratedWhite: 1.0, alpha: 0.94)))

        let contentSize = content.size()
        content.draw(at: CGPoint(x: rect.minX + labelWidth + contentGap, y: rect.midY - contentSize.height / 2.0 + 0.5))
    }

    private func hudContentFontSize(for rows: [LimitHUDRow], maxWidth: CGFloat) -> CGFloat {
        let longestText = rows
            .map { "\($0.remainingText) \($0.resetText)" }
            .max { $0.count < $1.count } ?? ""
        for fontSize in stride(from: 10.8, through: 8.4, by: -0.2) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
            ]
            if NSAttributedString(string: longestText, attributes: attrs).size().width <= maxWidth {
                return fontSize
            }
        }
        return 8.4
    }

    private func hudSegment(_ text: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: color
            ]
        )
    }

    private func drawHUDText(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: text, attributes: attrs).draw(in: rect)
    }

    private func limitLabel(for bucket: LimitBucket, fallback: String) -> String {
        if fallback == "5h" || fallback == "Week" {
            return fallback
        }
        guard let minutes = bucket.windowMinutes else { return fallback }
        if abs(minutes - 300.0) <= 10.0 {
            return "5h"
        }
        if minutes >= 60.0 * 24.0 * 6.0 {
            return "Week"
        }
        if minutes >= 60.0 {
            return "\(Int((minutes / 60.0).rounded()))h"
        }
        return "\(Int(max(1.0, minutes.rounded())))m"
    }

    private func formatResetText(for bucket: LimitBucket) -> String {
        guard let resetAt = bucket.resetAt else {
            return "--"
        }

        let resetDate = Date(timeIntervalSince1970: resetAt)
        let seconds = resetDate.timeIntervalSince(Date())
        if seconds <= 0 {
            return "now"
        }
        if seconds < 24.0 * 60.0 * 60.0 {
            return "in \(formatResetDuration(seconds))"
        }
        return formatWeekdayTime(resetDate)
    }

    private func formatResetDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(seconds / 60.0)))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }

    private func formatWeekdayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE H:mm"
        return formatter.string(from: date)
    }

    private func drawModelLimitDots(_ context: CGContext, center: CGPoint, radius: CGFloat, state: LimitState) {
        let dots = Array(state.additional.prefix(8))
        guard dots.count > 0 else { return }
        context.saveGState()
        let opacity = clampOpacity(opacitySettings.primary)
        for (index, item) in dots.enumerated() {
            let angle = -CGFloat.pi / 2.0 + CGFloat(index) / CGFloat(max(dots.count, 1)) * CGFloat.pi * 2.0
            let dot = point(center: center, radius: radius, angle: angle)
            let color = color(forRemaining: item.bucket.remainingPercent, role: .primary)
            context.setShadow(offset: .zero, blur: 5.0, color: color.withAlphaComponent(0.35 * opacity).cgColor)
            context.setFillColor(color.withAlphaComponent(0.82 * opacity).cgColor)
            context.fillEllipse(in: CGRect(x: dot.x - 2.4, y: dot.y - 2.4, width: 4.8, height: 4.8))
        }
        context.restoreGState()
    }

    private func color(forRemaining remaining: Double, role: RingRole) -> NSColor {
        if remaining <= 12 {
            return NSColor(calibratedRed: 1.00, green: 0.26, blue: 0.22, alpha: 0.96)
        }
        if remaining <= 30 {
            return NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.20, alpha: 0.96)
        }
        if role == .secondary {
            return colorPalette.secondary
        }
        return colorPalette.primary
    }

    private func opacity(for role: RingRole) -> CGFloat {
        role == .primary ? opacitySettings.primary : opacitySettings.secondary
    }

    private func clampOpacity(_ opacity: CGFloat) -> CGFloat {
        min(max(opacity, 0.0), 1.0)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent.rounded() - percent) < 0.05 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

final class LimitRingView: NSView {
    var state: LimitState = .empty {
        didSet { needsDisplay = true }
    }
    var phase: Double = 0 {
        didSet { needsDisplay = true }
    }
    var showsReadout: Bool = false {
        didSet { needsDisplay = true }
    }
    var colorPalette: RingColorPalette = .default {
        didSet { needsDisplay = true }
    }
    var opacitySettings: RingOpacitySettings = .default {
        didSet { needsDisplay = true }
    }
    var ringCenter: CGPoint? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        LimitRingRenderer(
            state: state,
            phase: phase,
            showsReadout: showsReadout,
            colorPalette: colorPalette,
            opacitySettings: opacitySettings,
            ringCenter: ringCenter
        ).draw(in: bounds)
    }
}

final class LimitRingsApp: NSObject {
    private enum RingTarget {
        case outer
        case inner
    }

    private let config: LimitRingsConfig
    private let stateReader: LimitStateReader
    private let frameReader: PetFrameReader
    private let panel: NSPanel
    private let ringView: LimitRingView
    private let stateQueue = DispatchQueue(label: "codex-pet-limit-rings.state-reader")
    private var statusItem: NSStatusItem?
    private var summaryItem: NSMenuItem?
    private var showRingsItem: NSMenuItem?
    private var outerColorPresetItems: [NSMenuItem] = []
    private var innerColorPresetItems: [NSMenuItem] = []
    private var outerCustomColorItem: NSMenuItem?
    private var innerCustomColorItem: NSMenuItem?
    private var outerOpacityPresetItems: [NSMenuItem] = []
    private var innerOpacityPresetItems: [NSMenuItem] = []
    private var stateTimer: Timer?
    private var frameTimer: Timer?
    private var animationTimer: Timer?
    private var mouseDownMonitor: Any?
    private var rightMouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var globalStateSource: DispatchSourceFileSystemObject?
    private var pendingGlobalStateWatcherRestart: DispatchWorkItem?
    private var pendingFrameUpdate: DispatchWorkItem?
    private var startTime = Date()
    private var currentPetFrameAppKit: CGRect?
    private var currentAvatarID: String?
    private var activeCustomColorTarget: RingTarget?
    private var dragCenterOffset: CGPoint?
    private var holdDraggedFrameUntil: Date?
    private var ringsVisible: Bool
    private var stateReadInFlight = false

    init(config: LimitRingsConfig) {
        self.config = config
        self.stateReader = LimitStateReader(logsPath: config.logsPath, authPath: config.authPath)
        self.frameReader = PetFrameReader(globalStatePath: config.globalStatePath)
        self.ringView = LimitRingView(frame: CGRect(origin: .zero, size: CGSize(width: config.fallbackSize, height: config.fallbackSize)))
        self.ringsVisible = UserDefaults.standard.object(forKey: ringsVisibleDefaultsKey) as? Bool ?? true
        self.panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: config.fallbackSize, height: config.fallbackSize)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = ringView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        super.init()
        applyCurrentRingColorPreset()
        applyCurrentRingOpacityPreset()
    }

    deinit {
        stateTimer?.invalidate()
        frameTimer?.invalidate()
        animationTimer?.invalidate()
        pendingGlobalStateWatcherRestart?.cancel()
        pendingFrameUpdate?.cancel()
        globalStateSource?.cancel()
        [mouseDownMonitor, rightMouseDownMonitor, mouseDragMonitor, mouseUpMonitor, mouseMoveMonitor].compactMap { $0 }.forEach {
            NSEvent.removeMonitor($0)
        }
    }

    func run() {
        installStatusMenu()
        updateState()
        updateFrame()
        installGlobalStateWatcher()
        updateRingVisibility()

        stateTimer = Timer.scheduledTimer(withTimeInterval: limitStatePollInterval, repeats: true) { [weak self] _ in
            self?.updateState()
        }
        frameTimer = Timer.scheduledTimer(withTimeInterval: petFrameFallbackPollInterval, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        installDragFollow()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ringView.phase = Date().timeIntervalSince(self.startTime) / 4.6
        }
    }

    private func updateState() {
        guard !stateReadInFlight else { return }
        stateReadInFlight = true
        stateQueue.async { [weak self] in
            guard let self else { return }
            let state = self.stateReader.readLatest()
            DispatchQueue.main.async {
                self.ringView.state = state
                self.updateSummaryMenuItem()
                self.stateReadInFlight = false
            }
        }
    }

    private func installGlobalStateWatcher() {
        pendingGlobalStateWatcherRestart?.cancel()
        pendingGlobalStateWatcherRestart = nil
        globalStateSource?.cancel()
        globalStateSource = nil

        let descriptor = open(config.globalStatePath.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleGlobalStateWatcherRestart(after: 1.0)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = self.globalStateSource?.data ?? []
            self.scheduleFrameUpdateFromGlobalState()
            if events.contains(.delete) || events.contains(.rename) {
                self.scheduleGlobalStateWatcherRestart(after: 0.2)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        globalStateSource = source
        source.resume()
    }

    private func scheduleGlobalStateWatcherRestart(after delay: TimeInterval) {
        pendingGlobalStateWatcherRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingGlobalStateWatcherRestart = nil
            self.installGlobalStateWatcher()
            self.scheduleFrameUpdateFromGlobalState()
        }
        pendingGlobalStateWatcherRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleFrameUpdateFromGlobalState() {
        pendingFrameUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingFrameUpdate = nil
            self.updateFrame()
            self.updateTooltip(at: NSEvent.mouseLocation)
        }
        pendingFrameUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + petFrameStateDebounceInterval, execute: work)
    }

    private func updateFrame() {
        if dragCenterOffset != nil {
            return
        }
        if let holdDraggedFrameUntil, Date() < holdDraggedFrameUntil {
            return
        }
        holdDraggedFrameUntil = nil

        guard let petFrame = frameReader.readPetFrameTopLeft() else {
            currentPetFrameAppKit = nil
            updateCurrentAvatarID(nil)
            dragCenterOffset = nil
            ringView.ringCenter = nil
            ringView.showsReadout = false
            panel.orderOut(nil)
            return
        }

        currentPetFrameAppKit = appKitRectFromTopLeft(petFrame)
        updateCurrentAvatarID(frameReader.readSelectedAvatarID())
        setPanelFrame(forPetFrameTopLeft: petFrame)
        if ringsVisible {
            panel.orderFrontRegardless()
        }
    }

    private func setPanelFrame(forPetFrameTopLeft petFrame: CGRect) {
        let ringSize = max(petFrame.width, petFrame.height) + ringPanelPadding * 2
        let panelSize = CGSize(width: ringSize, height: ringSize + readoutBottomExtension)
        let topLeft = CGPoint(x: petFrame.midX - ringSize / 2, y: petFrame.midY - ringSize / 2)
        let origin = appKitOriginFromTopLeft(topLeft, size: panelSize)

        ringView.ringCenter = CGPoint(x: panelSize.width / 2, y: ringSize / 2 + readoutBottomExtension)
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.title = ""
            button.image = makeStatusBarIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Codex Pet Limit Rings"
        }

        let menu = NSMenu()
        let summary = NSMenuItem(title: "Waiting for Codex limit data", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        summaryItem = summary

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "Show Rings", action: #selector(toggleRings(_:)), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        showRingsItem = showItem

        let colorItem = NSMenuItem(title: "Ring Colors", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        let outerColorItem = NSMenuItem(title: "Outer Ring", action: nil, keyEquivalent: "")
        let outerColorMenu = NSMenu()
        outerColorPresetItems = makeRingColorPresetItems(action: #selector(selectOuterRingColorPreset(_:)), menu: outerColorMenu)
        outerColorMenu.addItem(.separator())
        outerCustomColorItem = makeCustomRingColorItem(title: "Custom...", action: #selector(chooseOuterCustomRingColor(_:)), menu: outerColorMenu)
        outerColorItem.submenu = outerColorMenu
        colorMenu.addItem(outerColorItem)

        let innerColorItem = NSMenuItem(title: "Inner Ring", action: nil, keyEquivalent: "")
        let innerColorMenu = NSMenu()
        innerColorPresetItems = makeRingColorPresetItems(action: #selector(selectInnerRingColorPreset(_:)), menu: innerColorMenu)
        innerColorMenu.addItem(.separator())
        innerCustomColorItem = makeCustomRingColorItem(title: "Custom...", action: #selector(chooseInnerCustomRingColor(_:)), menu: innerColorMenu)
        innerColorItem.submenu = innerColorMenu
        colorMenu.addItem(innerColorItem)

        colorMenu.addItem(.separator())
        let resetColorItem = NSMenuItem(title: "Reset This Pet", action: #selector(resetRingColorForCurrentPet(_:)), keyEquivalent: "")
        resetColorItem.target = self
        colorMenu.addItem(resetColorItem)
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        let opacityItem = NSMenuItem(title: "Ring Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        let outerOpacityItem = NSMenuItem(title: "Outer Ring", action: nil, keyEquivalent: "")
        let outerOpacityMenu = NSMenu()
        outerOpacityPresetItems = makeRingOpacityPresetItems(action: #selector(selectOuterRingOpacityPreset(_:)), menu: outerOpacityMenu)
        outerOpacityItem.submenu = outerOpacityMenu
        opacityMenu.addItem(outerOpacityItem)

        let innerOpacityItem = NSMenuItem(title: "Inner Ring", action: nil, keyEquivalent: "")
        let innerOpacityMenu = NSMenu()
        innerOpacityPresetItems = makeRingOpacityPresetItems(action: #selector(selectInnerRingOpacityPreset(_:)), menu: innerOpacityMenu)
        innerOpacityItem.submenu = innerOpacityMenu
        opacityMenu.addItem(innerOpacityItem)

        opacityMenu.addItem(.separator())
        let resetOpacityItem = NSMenuItem(title: "Reset This Pet", action: #selector(resetRingOpacityForCurrentPet(_:)), keyEquivalent: "")
        resetOpacityItem.target = self
        opacityMenu.addItem(resetOpacityItem)
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Codex Pet Limit Rings", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        updateSummaryMenuItem()
        updateShowRingsMenuItem()
        updateRingColorMenuItems()
        updateRingOpacityMenuItems()
    }

    private func makeRingColorPresetItems(action: Selector, menu: NSMenu) -> [NSMenuItem] {
        RingColorPreset.all.map { preset in
            let item = NSMenuItem(title: preset.title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            menu.addItem(item)
            return item
        }
    }

    private func makeCustomRingColorItem(title: String, action: Selector, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func makeRingOpacityPresetItems(action: Selector, menu: NSMenu) -> [NSMenuItem] {
        RingOpacityPreset.all.map { preset in
            let item = NSMenuItem(title: preset.title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            menu.addItem(item)
            return item
        }
    }

    private func makeStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        let outer = NSBezierPath()
        outer.appendArc(
            withCenter: NSPoint(x: 9, y: 9),
            radius: 6.7,
            startAngle: 22,
            endAngle: 338,
            clockwise: false
        )
        outer.lineWidth = 2.0
        outer.lineCapStyle = .round
        outer.stroke()

        let inner = NSBezierPath()
        inner.appendArc(
            withCenter: NSPoint(x: 9, y: 9),
            radius: 3.6,
            startAngle: 210,
            endAngle: 82,
            clockwise: false
        )
        inner.lineWidth = 1.6
        inner.lineCapStyle = .round
        inner.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func updateSummaryMenuItem() {
        guard let summaryItem else { return }
        let primary = ringView.state.primary.map { "Short \(formatPercent($0.remainingPercent))" }
        let secondary = ringView.state.secondary.map { "Weekly \(formatPercent($0.remainingPercent))" }
        let pieces = [primary, secondary].compactMap { $0 }
        if pieces.isEmpty {
            summaryItem.title = "Waiting for Codex limit data"
        } else {
            let source = ringView.state.source == "live" ? "Live" : "Cached"
            summaryItem.title = "\(source) " + pieces.joined(separator: " | ")
        }
    }

    private func updateShowRingsMenuItem() {
        showRingsItem?.state = ringsVisible ? .on : .off
    }

    private func updateRingColorMenuItems() {
        let outerID = currentOuterRingColorPreset().id
        let innerID = currentInnerRingColorPreset().id
        let outerUsesCustom = currentCustomRingColor(prefix: outerRingCustomColorDefaultsPrefix) != nil
        let innerUsesCustom = currentCustomRingColor(prefix: innerRingCustomColorDefaultsPrefix) != nil
        for item in outerColorPresetItems {
            item.state = !outerUsesCustom && (item.representedObject as? String) == outerID ? .on : .off
        }
        for item in innerColorPresetItems {
            item.state = !innerUsesCustom && (item.representedObject as? String) == innerID ? .on : .off
        }
        outerCustomColorItem?.state = outerUsesCustom ? .on : .off
        innerCustomColorItem?.state = innerUsesCustom ? .on : .off
    }

    private func updateRingOpacityMenuItems() {
        let outerID = currentOuterRingOpacityPreset().id
        let innerID = currentInnerRingOpacityPreset().id
        for item in outerOpacityPresetItems {
            item.state = (item.representedObject as? String) == outerID ? .on : .off
        }
        for item in innerOpacityPresetItems {
            item.state = (item.representedObject as? String) == innerID ? .on : .off
        }
    }

    private func updateRingVisibility() {
        updateShowRingsMenuItem()
        if ringsVisible, currentPetFrameAppKit != nil {
            panel.orderFrontRegardless()
            updateTooltip(at: NSEvent.mouseLocation)
        } else {
            ringView.showsReadout = false
            panel.orderOut(nil)
        }
    }

    private func setRingsVisible(_ visible: Bool) {
        ringsVisible = visible
        UserDefaults.standard.set(visible, forKey: ringsVisibleDefaultsKey)
        updateRingVisibility()
    }

    private func updateCurrentAvatarID(_ avatarID: String?) {
        guard currentAvatarID != avatarID else { return }
        currentAvatarID = avatarID
        applyCurrentRingColorPreset()
        applyCurrentRingOpacityPreset()
        updateRingColorMenuItems()
        updateRingOpacityMenuItems()
    }

    private func currentOuterRingColorPreset() -> RingColorPreset {
        currentRingColorPreset(prefix: outerRingColorPresetDefaultsPrefix)
    }

    private func currentInnerRingColorPreset() -> RingColorPreset {
        currentRingColorPreset(prefix: innerRingColorPresetDefaultsPrefix)
    }

    private func currentRingColorPreset(prefix: String) -> RingColorPreset {
        let defaults = UserDefaults.standard
        let petPresetID = defaults.string(forKey: ringColorDefaultsKey(prefix: prefix, avatarID: currentAvatarID))
        let fallbackPresetID = currentAvatarID == nil ? nil : defaults.string(forKey: ringColorDefaultsKey(prefix: prefix, avatarID: nil))
        let legacyPetPresetID = defaults.string(forKey: legacyRingColorDefaultsKey(for: currentAvatarID))
        let legacyFallbackPresetID = currentAvatarID == nil ? nil : defaults.string(forKey: legacyRingColorDefaultsKey(for: nil))
        return RingColorPreset.preset(for: petPresetID ?? fallbackPresetID ?? legacyPetPresetID ?? legacyFallbackPresetID)
    }

    private func applyCurrentRingColorPreset() {
        ringView.colorPalette = RingColorPalette(
            primary: currentOuterRingColor(),
            secondary: currentInnerRingColor()
        )
    }

    private func currentOuterRingColor() -> NSColor {
        if let customColor = currentCustomRingColor(prefix: outerRingCustomColorDefaultsPrefix) {
            return customColor.withAlphaComponent(0.96)
        }
        return currentOuterRingColorPreset().palette.primary
    }

    private func currentInnerRingColor() -> NSColor {
        if let customColor = currentCustomRingColor(prefix: innerRingCustomColorDefaultsPrefix) {
            return customColor.withAlphaComponent(0.92)
        }
        return currentInnerRingColorPreset().palette.secondary
    }

    private func currentOuterRingOpacityPreset() -> RingOpacityPreset {
        currentRingOpacityPreset(prefix: outerRingOpacityPresetDefaultsPrefix)
    }

    private func currentInnerRingOpacityPreset() -> RingOpacityPreset {
        currentRingOpacityPreset(prefix: innerRingOpacityPresetDefaultsPrefix)
    }

    private func currentRingOpacityPreset(prefix: String) -> RingOpacityPreset {
        let defaults = UserDefaults.standard
        let petPresetID = defaults.string(forKey: ringOpacityDefaultsKey(prefix: prefix, avatarID: currentAvatarID))
        let fallbackPresetID = currentAvatarID == nil ? nil : defaults.string(forKey: ringOpacityDefaultsKey(prefix: prefix, avatarID: nil))
        return RingOpacityPreset.preset(for: petPresetID ?? fallbackPresetID)
    }

    private func applyCurrentRingOpacityPreset() {
        ringView.opacitySettings = RingOpacitySettings(
            primary: currentOuterRingOpacityPreset().opacity,
            secondary: currentInnerRingOpacityPreset().opacity
        )
    }

    private func ringColorDefaultsKey(prefix: String, avatarID: String?) -> String {
        prefix + (avatarID ?? defaultAvatarColorKey)
    }

    private func customRingColorDefaultsKey(prefix: String, avatarID: String?) -> String {
        prefix + (avatarID ?? defaultAvatarColorKey)
    }

    private func currentCustomRingColor(prefix: String) -> NSColor? {
        let key = customRingColorDefaultsKey(prefix: prefix, avatarID: currentAvatarID)
        return decodeRingColor(UserDefaults.standard.string(forKey: key))
    }

    private func customColorPrefix(forColorPresetPrefix prefix: String) -> String {
        prefix == outerRingColorPresetDefaultsPrefix ? outerRingCustomColorDefaultsPrefix : innerRingCustomColorDefaultsPrefix
    }

    private func encodeRingColor(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let red = colorComponentByte(rgb.redComponent)
        let green = colorComponentByte(rgb.greenComponent)
        let blue = colorComponentByte(rgb.blueComponent)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func decodeRingColor(_ rawValue: String?) -> NSColor? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            return nil
        }
        let red = CGFloat((number >> 16) & 0xFF) / 255.0
        let green = CGFloat((number >> 8) & 0xFF) / 255.0
        let blue = CGFloat(number & 0xFF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    private func colorComponentByte(_ component: CGFloat) -> Int {
        Int(round(min(max(component, 0.0), 1.0) * 255.0))
    }

    private func ringOpacityDefaultsKey(prefix: String, avatarID: String?) -> String {
        prefix + (avatarID ?? defaultAvatarColorKey)
    }

    private func legacyRingColorDefaultsKey(for avatarID: String?) -> String {
        ringColorPresetDefaultsPrefix + (avatarID ?? defaultAvatarColorKey)
    }

    @objc private func toggleRings(_ sender: NSMenuItem) {
        setRingsVisible(!ringsVisible)
    }

    @objc private func selectOuterRingColorPreset(_ sender: NSMenuItem) {
        selectRingColorPreset(sender, prefix: outerRingColorPresetDefaultsPrefix)
    }

    @objc private func selectInnerRingColorPreset(_ sender: NSMenuItem) {
        selectRingColorPreset(sender, prefix: innerRingColorPresetDefaultsPrefix)
    }

    private func selectRingColorPreset(_ sender: NSMenuItem, prefix: String) {
        guard let presetID = sender.representedObject as? String else { return }
        UserDefaults.standard.set(presetID, forKey: ringColorDefaultsKey(prefix: prefix, avatarID: currentAvatarID))
        UserDefaults.standard.removeObject(forKey: customRingColorDefaultsKey(prefix: customColorPrefix(forColorPresetPrefix: prefix), avatarID: currentAvatarID))
        applyCurrentRingColorPreset()
        updateRingColorMenuItems()
    }

    @objc private func chooseOuterCustomRingColor(_ sender: NSMenuItem) {
        openCustomRingColorPanel(for: .outer)
    }

    @objc private func chooseInnerCustomRingColor(_ sender: NSMenuItem) {
        openCustomRingColorPanel(for: .inner)
    }

    private func openCustomRingColorPanel(for target: RingTarget) {
        activeCustomColorTarget = target
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(customRingColorChanged(_:)))
        panel.color = target == .outer ? currentOuterRingColor() : currentInnerRingColor()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
    }

    @objc private func customRingColorChanged(_ sender: NSColorPanel) {
        guard let target = activeCustomColorTarget else { return }
        let prefix = target == .outer ? outerRingCustomColorDefaultsPrefix : innerRingCustomColorDefaultsPrefix
        let presetPrefix = target == .outer ? outerRingColorPresetDefaultsPrefix : innerRingColorPresetDefaultsPrefix
        UserDefaults.standard.set(encodeRingColor(sender.color), forKey: customRingColorDefaultsKey(prefix: prefix, avatarID: currentAvatarID))
        UserDefaults.standard.removeObject(forKey: ringColorDefaultsKey(prefix: presetPrefix, avatarID: currentAvatarID))
        applyCurrentRingColorPreset()
        updateRingColorMenuItems()
    }

    @objc private func selectOuterRingOpacityPreset(_ sender: NSMenuItem) {
        selectRingOpacityPreset(sender, prefix: outerRingOpacityPresetDefaultsPrefix)
    }

    @objc private func selectInnerRingOpacityPreset(_ sender: NSMenuItem) {
        selectRingOpacityPreset(sender, prefix: innerRingOpacityPresetDefaultsPrefix)
    }

    private func selectRingOpacityPreset(_ sender: NSMenuItem, prefix: String) {
        guard let presetID = sender.representedObject as? String else { return }
        UserDefaults.standard.set(presetID, forKey: ringOpacityDefaultsKey(prefix: prefix, avatarID: currentAvatarID))
        applyCurrentRingOpacityPreset()
        updateRingOpacityMenuItems()
    }

    @objc private func resetRingColorForCurrentPet(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ringColorDefaultsKey(prefix: outerRingColorPresetDefaultsPrefix, avatarID: currentAvatarID))
        defaults.removeObject(forKey: ringColorDefaultsKey(prefix: innerRingColorPresetDefaultsPrefix, avatarID: currentAvatarID))
        defaults.removeObject(forKey: customRingColorDefaultsKey(prefix: outerRingCustomColorDefaultsPrefix, avatarID: currentAvatarID))
        defaults.removeObject(forKey: customRingColorDefaultsKey(prefix: innerRingCustomColorDefaultsPrefix, avatarID: currentAvatarID))
        defaults.removeObject(forKey: legacyRingColorDefaultsKey(for: currentAvatarID))
        applyCurrentRingColorPreset()
        updateRingColorMenuItems()
    }

    @objc private func resetRingOpacityForCurrentPet(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ringOpacityDefaultsKey(prefix: outerRingOpacityPresetDefaultsPrefix, avatarID: currentAvatarID))
        defaults.removeObject(forKey: ringOpacityDefaultsKey(prefix: innerRingOpacityPresetDefaultsPrefix, avatarID: currentAvatarID))
        applyCurrentRingOpacityPreset()
        updateRingOpacityMenuItems()
    }

    @objc private func refreshNow(_ sender: NSMenuItem) {
        updateState()
        updateFrame()
        updateRingVisibility()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func installDragFollow() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleLeftMouseDown(event)
            }
        }
        rightMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.openCodexSettingsIfNeeded(at: NSEvent.mouseLocation)
            }
        }
        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.continueDragFollow(at: NSEvent.mouseLocation)
            }
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.endDragFollow()
            }
        }
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateTooltip(at: NSEvent.mouseLocation)
            }
        }
    }

    private func handleLeftMouseDown(_ event: NSEvent) {
        beginDragFollowIfNeeded(at: NSEvent.mouseLocation)
    }

    private func openCodexSettingsIfNeeded(at mouse: CGPoint) {
        guard isPetActionTarget(at: mouse) else { return }
        NSWorkspace.shared.open(codexSettingsURL)
    }

    private func isPetActionTarget(at mouse: CGPoint) -> Bool {
        guard ringsVisible else { return false }
        updateFrame()
        guard currentPetFrameAppKit != nil else { return false }
        return isHoveringRingOrPet(mouse)
    }

    private func beginDragFollowIfNeeded(at mouse: CGPoint) {
        guard ringsVisible else { return }
        updateFrame()
        guard let currentPetFrameAppKit else { return }
        let hitTarget = currentPetFrameAppKit.insetBy(dx: -24, dy: -24)
        guard hitTarget.contains(mouse) else { return }

        let ringCenter = ringCenterInPanel()
        let ringCenterOnScreen = CGPoint(x: panel.frame.minX + ringCenter.x, y: panel.frame.minY + ringCenter.y)
        dragCenterOffset = CGPoint(x: ringCenterOnScreen.x - mouse.x, y: ringCenterOnScreen.y - mouse.y)
        holdDraggedFrameUntil = nil
    }

    private func continueDragFollow(at mouse: CGPoint) {
        guard let offset = dragCenterOffset else { return }
        let size = panel.frame.size
        let center = CGPoint(x: mouse.x + offset.x, y: mouse.y + offset.y)
        let ringCenter = ringCenterInPanel()
        let origin = CGPoint(x: center.x - ringCenter.x, y: center.y - ringCenter.y)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        ringView.showsReadout = false
    }

    private func endDragFollow() {
        guard dragCenterOffset != nil else { return }
        dragCenterOffset = nil
        holdDraggedFrameUntil = Date().addingTimeInterval(1.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) { [weak self] in
            self?.updateFrame()
        }
    }

    private func updateTooltip(at mouse: CGPoint) {
        if !ringsVisible || currentPetFrameAppKit == nil || dragCenterOffset != nil {
            ringView.showsReadout = false
            return
        }

        ringView.showsReadout = isHoveringRingOrPet(mouse)
    }

    private func isHoveringRingOrPet(_ mouse: CGPoint) -> Bool {
        if let petFrame = currentPetFrameAppKit,
           petFrame.insetBy(dx: -10, dy: -10).contains(mouse) {
            return true
        }

        let frame = panel.frame
        guard frame.insetBy(dx: -4, dy: -4).contains(mouse) else {
            return false
        }

        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let center = ringCenterInPanel()
        let distance = hypot(local.x - center.x, local.y - center.y)
        let radius = min(frame.width, frame.height) * 0.5 - 16.0
        return distance >= radius - 24.0 && distance <= radius + 19.0
    }

    private func ringCenterInPanel() -> CGPoint {
        ringView.ringCenter ?? CGPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
    }

    private func appKitOriginFromTopLeft(_ topLeft: CGPoint, size: CGSize) -> CGPoint {
        let topLeftRect = CGRect(origin: topLeft, size: size)
        guard let screen = screenForTopLeftRect(topLeftRect) else {
            return CGPoint(x: topLeft.x, y: max(0, config.fallbackSize - topLeft.y))
        }

        let screenTopLeftFrame = topLeftFrame(for: screen)
        let localX = topLeft.x - screenTopLeftFrame.minX
        let localY = topLeft.y - screenTopLeftFrame.minY
        return CGPoint(x: screen.frame.minX + localX, y: screen.frame.maxY - localY - size.height)
    }

    private func appKitRectFromTopLeft(_ rect: CGRect) -> CGRect {
        guard let screen = screenForTopLeftRect(rect) else {
            return rect
        }

        let screenTopLeftFrame = topLeftFrame(for: screen)
        let localX = rect.minX - screenTopLeftFrame.minX
        let localY = rect.minY - screenTopLeftFrame.minY
        return CGRect(
            x: screen.frame.minX + localX,
            y: screen.frame.maxY - localY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func screenForTopLeftRect(_ rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let screen = screens.first(where: { topLeftFrame(for: $0).contains(center) }) {
            return screen
        }

        return screens.min {
            distanceSquared(center, to: topLeftFrame(for: $0)) < distanceSquared(center, to: topLeftFrame(for: $1))
        }
    }

    private func topLeftFrame(for screen: NSScreen) -> CGRect {
        let primaryMaxY = (primaryScreen() ?? NSScreen.screens.first)?.frame.maxY ?? screen.frame.maxY
        return CGRect(
            x: screen.frame.minX,
            y: primaryMaxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private func primaryScreen() -> NSScreen? {
        NSScreen.screens.first { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 }
    }

    private func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent.rounded() - percent) < 0.05 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

func renderPreview(config: LimitRingsConfig) -> Bool {
    let state = LimitStateReader(logsPath: config.logsPath, authPath: config.authPath).readLatest()
    let size = CGSize(width: config.fallbackSize, height: config.fallbackSize)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    LimitRingRenderer(state: state, phase: 0.18, showsReadout: true).draw(in: CGRect(origin: .zero, size: size))
    image.unlockFocus()

    guard let previewPath = config.previewPath,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        return false
    }

    do {
        try FileManager.default.createDirectory(at: previewPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: previewPath)
        return true
    } catch {
        fputs("codex-pet-limit-rings: could not write preview: \(error)\n", stderr)
        return false
    }
}

func parseConfig() -> LimitRingsConfig? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let codexHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)
    var config = LimitRingsConfig(
        codexHome: codexHome,
        globalStatePath: codexHome.appendingPathComponent(".codex-global-state.json"),
        logsPath: defaultLogsPath(codexHome: codexHome),
        authPath: codexHome.appendingPathComponent("auth.json"),
        previewPath: nil
    )

    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--help", "-h":
            print("""
            Usage: codex-pet-limit-rings [--preview PATH] [--codex-home PATH] [--logs PATH] [--auth PATH] [--state PATH]

            Draws a transparent Codex rate-limit rings around the current pet.
            """)
            exit(0)
        case "--preview":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.previewPath = URL(fileURLWithPath: value)
        case "--codex-home":
            guard let value = args.first else { return nil }
            args.removeFirst()
            let url = URL(fileURLWithPath: value)
            config.codexHome = url
            config.globalStatePath = url.appendingPathComponent(".codex-global-state.json")
            config.logsPath = defaultLogsPath(codexHome: url)
            config.authPath = url.appendingPathComponent("auth.json")
        case "--logs":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.logsPath = URL(fileURLWithPath: value)
        case "--auth":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.authPath = URL(fileURLWithPath: value)
        case "--state":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.globalStatePath = URL(fileURLWithPath: value)
        case "--size":
            guard let value = args.first, let size = Double(value) else { return nil }
            args.removeFirst()
            config.fallbackSize = CGFloat(size)
        default:
            fputs("codex-pet-limit-rings: unknown argument \(arg)\n", stderr)
            return nil
        }
    }

    return config
}

func defaultLogsPath(codexHome: URL) -> URL {
    let logs2 = codexHome.appendingPathComponent("logs_2.sqlite")
    if FileManager.default.fileExists(atPath: logs2.path) {
        return logs2
    }
    return codexHome.appendingPathComponent("logs_1.sqlite")
}

guard let config = parseConfig() else {
    fputs("codex-pet-limit-rings: invalid arguments. Use --help.\n", stderr)
    exit(2)
}

if config.previewPath != nil {
    exit(renderPreview(config: config) ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let rings = LimitRingsApp(config: config)
rings.run()
app.run()
