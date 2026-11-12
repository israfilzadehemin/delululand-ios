import CoreGraphics
import Foundation
import SwiftUI

/// SVG path data (`d="M50 13 C73 12 …"`) as a SwiftUI path, for the hand-drawn marks the web and
/// Android draw from the same strings (board reactions, the react slot). All commands, absolute and
/// relative, including arcs.
public enum PathData {
    private static let cache = NSCache<NSString, PathBox>()

    private final class PathBox {
        let path: Path
        init(_ path: Path) { self.path = path }
    }

    public static func path(_ d: String) -> Path {
        if let hit = cache.object(forKey: d as NSString) { return hit.path }
        let path = parse(d)
        cache.setObject(PathBox(path), forKey: d as NSString)
        return path
    }

    // MARK: Tokens

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokens(_ d: String) -> [Token] {
        var out: [Token] = []
        var number = ""
        func flush() {
            if !number.isEmpty, let v = Double(number) { out.append(.number(CGFloat(v))) }
            number = ""
        }
        for c in d {
            if c.isLetter, c != "e", c != "E" {
                flush()
                out.append(.command(c))
            } else if c == "-" || c == "+" {
                if let last = number.last, last == "e" || last == "E" {
                    number.append(c)
                } else {
                    flush()
                    number.append(c)
                }
            } else if c == "." {
                if number.contains("."), !(number.contains("e") || number.contains("E")) {
                    flush()
                }
                number.append(c)
            } else if c.isNumber || c == "e" || c == "E" {
                number.append(c)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    // MARK: Parse

    private static func parse(_ d: String) -> Path {
        var path = Path()
        let list = tokens(d)
        var i = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuad: CGPoint?

        func next() -> CGFloat? {
            guard i < list.count, case let .number(v) = list[i] else { return nil }
            i += 1
            return v
        }
        func hasNumber() -> Bool {
            guard i < list.count, case .number = list[i] else { return false }
            return true
        }

        while i < list.count {
            if case let .command(c) = list[i] {
                command = c
                i += 1
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased().first! {
            case "M":
                guard let x = next(), let y = next() else { return path }
                current = CGPoint(x: base.x + x, y: base.y + y)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
                lastControl = nil
                lastQuad = nil
            case "L":
                guard let x = next(), let y = next() else { return path }
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addLine(to: current)
                lastControl = nil
                lastQuad = nil
            case "H":
                guard let x = next() else { return path }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
                lastQuad = nil
            case "V":
                guard let y = next() else { return path }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current)
                lastControl = nil
                lastQuad = nil
            case "C":
                guard let x1 = next(), let y1 = next(), let x2 = next(), let y2 = next(), let x = next(), let y = next() else { return path }
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1)
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
                lastQuad = nil
            case "S":
                guard let x2 = next(), let y2 = next(), let x = next(), let y = next() else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
                lastQuad = nil
            case "Q":
                guard let x1 = next(), let y1 = next(), let x = next(), let y = next() else { return path }
                let c = CGPoint(x: base.x + x1, y: base.y + y1)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: c)
                lastQuad = c
                lastControl = nil
            case "T":
                guard let x = next(), let y = next() else { return path }
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: c)
                lastQuad = c
                lastControl = nil
            case "A":
                guard let rx = next(), let ry = next(), let rotation = next(), let large = next(), let sweep = next(),
                      let x = next(), let y = next() else { return path }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                arc(&path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large != 0, sweep: sweep != 0)
                current = end
                lastControl = nil
                lastQuad = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
                lastQuad = nil
                // A number straight after Z belongs to no command; skip it.
                while hasNumber() { i += 1 }
            default:
                i += 1
            }
        }
        return path
    }

    /// SVG elliptical arc (endpoint form) as cubic curves (SVG 1.1 implementation notes, F.6.5).
    private static func arc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, rx rIn: CGFloat, ry ryIn: CGFloat,
                            rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 || p1 == p2 {
            path.addLine(to: p2)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4 / 3 * tan(step / 4)
        var a = theta1
        for _ in 0 ..< segments {
            let cosA = cos(a), sinA = sin(a)
            let b = a + step
            let cosB = cos(b), sinB = sin(b)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cx + rx * x * cosPhi - ry * y * sinPhi, y: cy + rx * x * sinPhi + ry * y * cosPhi)
            }
            let c1 = point(cosA - t * sinA, sinA + t * cosA)
            let c2 = point(cosB + t * sinB, sinB - t * cosB)
            let end = point(cosB, sinB)
            path.addCurve(to: end, control1: c1, control2: c2)
            a = b
        }
    }
}

/// A path drawn on a 100-unit grid, scaled to the frame (the board's marks).
public struct GridShape: Shape {
    let d: String
    let grid: CGFloat

    public init(_ d: String, grid: CGFloat = 100) {
        self.d = d
        self.grid = grid
    }

    public func path(in rect: CGRect) -> Path {
        PathData.path(d).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / grid, y: rect.height / grid)
        )
    }
}
