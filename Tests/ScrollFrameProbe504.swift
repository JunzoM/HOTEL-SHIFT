import Foundation
import UIKit

@MainActor final class ScrollFrameCounter504: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    var gaps: [Double] = []
    var sample: (() -> Void)?
    func start() {
        let display = CADisplayLink(target: self, selector: #selector(tick(_:)))
        display.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        display.add(to: .main, forMode: .common); link = display
    }
    @objc private func tick(_ sender: CADisplayLink) {
        if let last { gaps.append((sender.timestamp-last)*1000) }
        last = sender.timestamp
        sample?()
    }
    func stop() { link?.invalidate(); link = nil }
}
@MainActor enum ScrollFrameProbe504 {
    private static func find(_ view: UIView, id: String) -> UIScrollView? {
        if view.accessibilityIdentifier == id, let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews { if let result = find(child, id: id) { return result } }
        return nil
    }
    static func run(output: String, requireHeader: Bool) async -> Bool {
        var body: UIScrollView?, root: UIView?
        for _ in 0..<50 {
            root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            if let root { body = find(root, id: "scheduleBodyHorizontal") }
            if body != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let body, let root else { return false }
        try? await Task.sleep(for: .seconds(1))
        body.setContentOffset(.zero, animated: false)
        let header = find(root, id: "scheduleDateHeader")
        let counter = ScrollFrameCounter504()
        var maximumHeaderError = 0.0
        counter.sample = { if let header { maximumHeaderError = max(maximumHeaderError, abs(header.contentOffset.x-body.contentOffset.x)) } }
        counter.start()
        let maximum = max(0, body.contentSize.width-body.bounds.width)
        for fraction in [0.8, 0.0, 0.6, 0.0] {
            body.setContentOffset(CGPoint(x:maximum*fraction,y:0), animated: true)
            try? await Task.sleep(for: .milliseconds(400))
        }
        try? await Task.sleep(for: .milliseconds(200))
        counter.stop()
        let error = header.map { abs($0.contentOffset.x-body.contentOffset.x) }
        let sorted = counter.gaps.sorted()
        let result: [String: Any] = [
            "environment": "Same iPad Pro Simulator, debug build, programmatic UIScrollView animation; not physical touch/FPS",
            "samples": sorted.count,
            "mean_frame_interval_ms": sorted.reduce(0,+)/Double(max(1,sorted.count)),
            "p95_frame_interval_ms": sorted.isEmpty ? 0 : sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))],
            "max_frame_interval_ms": sorted.last ?? 0,
            "frames_over_25ms": sorted.filter{$0>25}.count,
            "final_offset": body.contentOffset.x,
            "header_error_points": error as Any? ?? NSNull(),
            "maximum_header_error_points": header == nil ? NSNull() : maximumHeaderError
        ]
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent(output)
        do { try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:url) } catch { return false }
        return !sorted.isEmpty && (!requireHeader || ((error ?? .infinity) < 1 && maximumHeaderError < 1))
    }
}
