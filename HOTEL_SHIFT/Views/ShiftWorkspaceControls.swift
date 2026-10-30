import SwiftUI

// FIXED479: One toolbar owns display/edit controls; the active surface handles commands.
@MainActor final class ShiftWorkspaceControls: ObservableObject {
    enum Command: Equatable { case undo, redo, toggleSelection, copyWeek }
    struct Request: Equatable {
        let id = UUID()
        let command: Command
    }
    @Published var editing = false
    @Published var department = "すべて"
    @Published var selecting = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var request: Request?
    func send(_ command: Command) { request = Request(command: command) }
    func reset() {
        editing = false; selecting = false; canUndo = false; canRedo = false; request = nil
    }
}

// Explicit flat styling avoids OS-version-dependent glass/capsule toolbars.
struct ScheduleToolbarButtonStyle: ButtonStyle {
    var prominent = false
    var scale: CGFloat = 1
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12 * scale, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.blue)
            .padding(.horizontal, 10 * scale).frame(minHeight: 30 * scale)
            .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 6 * scale), interactive: true, tint: prominent ? .blue : nil))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

// Scoped to the frontmost scene so commands act on the visible shift workspace.
struct ShiftKeyboardActions {
    let canUndo: Bool
    let canRedo: Bool
    let canExport: Bool
    let undo: () -> Void
    let redo: () -> Void
    let exportPDF: () -> Void
}
private struct ShiftKeyboardActionsKey: FocusedValueKey {
    typealias Value = ShiftKeyboardActions
}
extension FocusedValues {
    var shiftKeyboardActions: ShiftKeyboardActions? {
        get { self[ShiftKeyboardActionsKey.self] }
        set { self[ShiftKeyboardActionsKey.self] = newValue }
    }
}
#if targetEnvironment(macCatalyst)
struct ShiftMacCommands: Commands {
    @FocusedValue(\.shiftKeyboardActions) private var actions
    var body: some Commands {
        CommandMenu("シフト") {
            Button("シフトを取り消す") { actions?.undo() }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(actions?.canUndo != true)
            Button("シフトをやり直す") { actions?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .option, .shift])
                .disabled(actions?.canRedo != true)
            Divider()
            Button("シフト表PDFを作成…") { actions?.exportPDF() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions?.canExport != true)
        }
    }
}
#endif


// Shared native tab appearance for phone screens, matching the staff workspace.
struct PhoneTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.pickerStyle(.segmented).controlSize(.regular).labelsHidden()
    }
}

// New SDK code is excluded by older compilers; runtime availability is checked separately.
struct AppGlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var interactive = false
    var tint: Color? = nil
    var clear = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(tint ?? Color(.systemBackground), in: shape)
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                let glass = clear ? Glass.clear : Glass.regular
                if let tint {
                    content.glassEffect(interactive ? glass.tint(tint).interactive() : glass.tint(tint), in: shape)
                } else {
                    content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
                }
            } else {
                fallback(content)
            }
            #else
            fallback(content)
            #endif
        }
    }
    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if let tint { content.background(tint.opacity(0.9), in: shape) }
        else {
            if clear { content.background(.ultraThinMaterial, in: shape) }
            else { content.background(.regularMaterial, in: shape) }
        }
    }
}

struct AppActionStyle: ViewModifier {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if workspaceAppearance.isDesktop {
            fallback(content)
        } else {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
        }
    }
    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if prominent { content.buttonStyle(.borderedProminent) }
        else { content.buttonStyle(.bordered) }
    }
}
