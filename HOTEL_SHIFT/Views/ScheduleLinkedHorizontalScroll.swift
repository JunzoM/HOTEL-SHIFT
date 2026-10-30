import SwiftUI
import UIKit

// UIKit moves the header directly; scrolling does not publish SwiftUI state.
final class ScheduleScrollLink {
    weak var header: UIScrollView?
    weak var body: UIScrollView?
    func reset() { body?.setContentOffset(.zero, animated: false); move(to: 0) }
    private(set) var offset: CGFloat = 0
    func move(to value: CGFloat) {
        offset = value
        header?.setContentOffset(CGPoint(x: value, y: 0), animated: false)
    }
}
struct ScheduleLinkedHeader<Content: View>: UIViewRepresentable {
    let link: ScheduleScrollLink
    let contentWidth: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.isScrollEnabled = false; scroll.clipsToBounds = true
        scroll.accessibilityIdentifier = "scheduleDateHeader"
        scroll.contentInsetAdjustmentBehavior = .never
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        context.coordinator.host = host
        link.header = scroll
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host?.rootView = content()
        context.coordinator.host?.view.frame = CGRect(x: 0, y: 0, width: contentWidth, height: height)
        scroll.contentSize = CGSize(width: contentWidth, height: height)
        link.header = scroll
        link.move(to: link.offset)
    }
    final class Coordinator { var host: UIHostingController<Content>? }
}
struct ScheduleLinkedHorizontalScroll<Content: View>: UIViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let resetKey: String
    let contentRevision: AnyHashable
    let link: ScheduleScrollLink
    @ViewBuilder let content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsHorizontalScrollIndicator = true
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.isDirectionalLockEnabled = true
        scroll.delegate = context.coordinator
        link.body = scroll
        scroll.accessibilityIdentifier = "scheduleBodyHorizontal"
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(host.view)
        let width = host.view.widthAnchor.constraint(equalToConstant: contentWidth)
        let height = host.view.heightAnchor.constraint(equalToConstant: contentHeight)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), width, height
        ])
        context.coordinator.host = host; context.coordinator.width = width; context.coordinator.height = height
        context.coordinator.key = resetKey; context.coordinator.revision = contentRevision
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self; coordinator.updating = true
        let resized = coordinator.width?.constant != contentWidth || coordinator.height?.constant != contentHeight
        let reset = coordinator.key != resetKey
        let changed = coordinator.revision != contentRevision
        if changed { coordinator.host?.rootView = content(); coordinator.revision = contentRevision }
        if resized { coordinator.width?.constant = contentWidth; coordinator.height?.constant = contentHeight }
        if reset { coordinator.key = resetKey; scroll.setContentOffset(.zero, animated: false) }
        if resized || reset || changed { scroll.layoutIfNeeded() }
        let clamped = min(max(0, contentWidth - scroll.bounds.width), max(0, scroll.contentOffset.x))
        if abs(clamped - scroll.contentOffset.x) > 0.1 { scroll.setContentOffset(CGPoint(x: clamped, y: 0), animated: false) }
        link.move(to: clamped)
        coordinator.updating = false
    }
    static func dismantleUIView(_ scroll: UIScrollView, coordinator: Coordinator) {
        scroll.delegate = nil; coordinator.host = nil
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ScheduleLinkedHorizontalScroll
        var host: UIHostingController<Content>?
        var width: NSLayoutConstraint?; var height: NSLayoutConstraint?
        var key = ""; var revision: AnyHashable?; var updating = false
        init(_ parent: ScheduleLinkedHorizontalScroll) { self.parent = parent }
        func scrollViewDidScroll(_ scroll: UIScrollView) {
            guard !updating else { return }
            parent.link.move(to: min(max(0, parent.contentWidth - scroll.bounds.width), max(0, scroll.contentOffset.x)))
        }
    }
}
