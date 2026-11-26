//
//  popup.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 11/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public final class PopupCache<T> {
    public var value: T?
    public var initialized: Bool = false
    
    public init() {}
    
    public func apply(_ value: T, visible: Bool, render: (T) -> Void) {
        self.value = value
        if visible || !self.initialized {
            render(value)
            self.initialized = true
        }
    }
    
    public func replay(render: (T) -> Void) {
        if let v = self.value { render(v) }
    }
}

public protocol Popup_p: NSView {
    var keyboardShortcut: [UInt16] { get }
    var sizeCallback: ((NSSize) -> Void)? { get set }
    
    func settings() -> NSView?
    
    func appear()
    func disappear()
    func setKeyboardShortcut(_ binding: [UInt16])
}

open class PopupWrapper: NSStackView, Popup_p {
    public var title: String
    public var keyboardShortcut: [UInt16] = []
    open var sizeCallback: ((NSSize) -> Void)? = nil
    
    public init(_ typ: ModuleType, frame: NSRect) {
        self.title = typ.stringValue
        self.keyboardShortcut = Store.shared.array(key: "\(typ.stringValue)_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: frame)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func settings() -> NSView? { return nil }
    open func appear() {}
    open func disappear() {}
    
    open func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "\(self.title)_popup_keyboardShortcut", value: binding)
    }
    
    public func apply<T>(_ value: T, to cache: PopupCache<T>, render: @escaping (T) -> Void) {
        DispatchQueue.main.async {
            cache.apply(value, visible: self.window?.isVisible ?? false, render: render)
        }
    }
    
    public func replay<T>(_ cache: PopupCache<T>, render: (T) -> Void) {
        cache.replay(render: render)
    }
}

public class PopupWindow: NSWindow, NSWindowDelegate {
    private let viewController: PopupViewController
    internal var locked: Bool = false
    internal var openedBy: widget_t? = nil
    
    public init(title: String, module: ModuleType, view: Popup_p?, visibilityCallback: @escaping (_ state: Bool) -> Void) {
        self.viewController = PopupViewController(module: module)
        self.viewController.setup(title: title, view: view)
        
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: self.viewController.view.frame.width,
                height: self.viewController.view.frame.height
            ),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        
        self.viewController.visibilityCallback = { [weak self] state in
            self?.locked = false
            visibilityCallback(state)
        }
        
        self.title = title
        self.titleVisibility = .hidden
        self.contentViewController = self.viewController
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .default
        self.collectionBehavior = .moveToActiveSpace
        self.backgroundColor = .clear
        self.hasShadow = true
        self.setIsVisible(false)
        self.delegate = self
    }
    
    public func windowWillMove(_ notification: Notification) {
        self.viewController.setCloseButton(true)
        self.locked = true
    }
    
    public func windowDidResignKey(_ notification: Notification) {
        if self.locked {
            return
        }
        
        self.viewController.setCloseButton(false)
        self.setIsVisible(false)
    }
}

internal class PopupViewController: NSViewController {
    fileprivate var visibilityCallback: (_ state: Bool) -> Void = {_ in }
    private var popup: PopupView
    
    public init(module: ModuleType) {
        self.popup = PopupView(frame: NSRect(
            x: 0,
            y: 0,
            width: Constants.Popup.width + (Constants.Popup.margins * 2),
            height: Constants.Popup.height + Constants.Popup.headerHeight + Constants.Popup.footerHeight
        ), module: module)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        self.view = self.popup
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        self.popup.appear()
        self.visibilityCallback(true)
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        self.popup.disappear()
        self.visibilityCallback(false)
    }
    
    fileprivate func setup(title: String, view: Popup_p?) {
        self.title = title
        self.popup.setTitle(title)
        self.popup.setView(view)
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        self.popup.setCloseButton(state)
    }
}

internal class PopupView: NSView {
    private var view: Popup_p? = nil
    
    private var foreground: NSView
    private var background: NSView
    
    private let header: HeaderView
    private let body: NSScrollView
    private let footer: GlassTuningView
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: self.frame.width, height: self.frame.height)
    }
    private var windowHeight: CGFloat?
    private var containerHeight: CGFloat?
    
    init(frame: NSRect, module: ModuleType) {
        self.header = HeaderView(frame: NSRect(
            x: 0,
            y: frame.height - Constants.Popup.headerHeight,
            width: frame.width,
            height: Constants.Popup.headerHeight
        ), module: module)
        self.body = NSScrollView(frame: NSRect(
            x: Constants.Popup.margins,
            y: Constants.Popup.margins + Constants.Popup.footerHeight,
            width: frame.width - Constants.Popup.margins*2,
            height: frame.height - self.header.frame.height - Constants.Popup.margins*2 - Constants.Popup.footerHeight
        ))
        self.footer = GlassTuningView(frame: NSRect(
            x: Constants.Popup.margins,
            y: 4,
            width: frame.width - Constants.Popup.margins*2,
            height: Constants.Popup.footerHeight
        ))
        self.windowHeight = NSScreen.main?.visibleFrame.height
        self.containerHeight = self.body.documentView?.frame.height
        
        if #available(macOS 26.0, *) {
            // Native Liquid Glass sheet. IMPORTANT: all interactive content
            // must live inside `contentView` — that is the only arrangement
            // NSGlassEffectView guarantees receives events and legibility
            // treatment (a glass view layered as a background sibling
            // swallows clicks for everything above it).
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = Constants.Popup.glassRadius
            // `.regular` + a strong tint floor makes the sheet read OPAQUE
            // (but still glass — adaptive material, rim lighting), while the
            // bubbles inside are the clear, refractive glass elements.
            glass.style = .regular
            let container = NSView(frame: frame)
            glass.contentView = container
            self.foreground = glass
            self.background = container
        } else {
            // Frosted emulation: blur + tint + luminous edge + specular sheen.
            let effect = NSVisualEffectView(frame: frame)
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.masksToBounds = true
            effect.layer?.cornerRadius = Constants.Popup.glassRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.borderWidth = 1
            self.foreground = effect

            self.background = NSView(frame: frame)
            self.background.wantsLayer = true
            self.foreground.addSubview(self.background)

            // Specular highlight falling from the top edge, like light hitting glass.
            let sheen = SheenView(frame: NSRect(x: 0, y: frame.height - 60, width: frame.width, height: 60))
            sheen.autoresizingMask = [.width, .minYMargin]
            self.background.addSubview(sheen)
        }

        super.init(frame: frame)
        
        self.body.drawsBackground = false
        self.body.translatesAutoresizingMaskIntoConstraints = true
        self.body.borderType = .noBorder
        self.body.hasVerticalScroller = true
        self.body.hasHorizontalScroller = false
        self.body.autohidesScrollers = true
        self.body.horizontalScrollElasticity = .none

        if #available(macOS 26.0, *) {
            // Event backstop. The glass sheet is composited OUT-OF-PROCESS by
            // the window server, so the app's own window surface is fully
            // transparent — and the window server click-throughs windows with
            // no opaque pixels, meaning mouse events never reach the app at
            // all (root cause of the "nothing is clickable" bug; in-process
            // event injection works fine). This near-invisible in-process
            // layer restores the window's hit region. Do not remove it.
            let backstop = NSView(frame: frame)
            backstop.wantsLayer = true
            backstop.autoresizingMask = [.width, .height]
            backstop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.02).cgColor
            backstop.layer?.cornerRadius = Constants.Popup.glassRadius
            backstop.layer?.cornerCurve = .continuous
            self.addSubview(backstop)

            // Header, body and footer live INSIDE the glass contentView.
            self.addSubview(self.foreground)
            self.background.addSubview(self.header)
            self.background.addSubview(self.body)
            self.background.addSubview(self.footer)
        } else {
            self.addSubview(self.foreground, positioned: .below, relativeTo: .none)
            self.addSubview(self.header)
            self.addSubview(self.body)
            self.addSubview(self.footer)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(self.glassLevelsChanged), name: .glassLevelsChanged, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .glassLevelsChanged, object: nil)
    }

    @objc private func glassLevelsChanged() {
        self.updateLayer()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Re-tint the glass when the system light/dark switch flips.
        self.updateLayer()
    }

    override func updateLayer() {
        let dark = self.isDarkModeEffective
        // GlassLevels.fill blends the slider level between a floor/ceiling
        // per appearance and never reaches full opacity, so the sheet always
        // keeps some glass refraction — and dark mode reliably reads dark
        // even over a bright wallpaper instead of just faintly whitening it.
        let fill = GlassLevels.fill(.background, dark: dark)
        if #available(macOS 26.0, *) {
            if let glass = self.foreground as? NSGlassEffectView {
                glass.tintColor = fill
            }
            // Luminous rim around the whole sheet so it reads as a distinct
            // surface against the desktop.
            self.layer?.cornerRadius = Constants.Popup.glassRadius
            self.layer?.cornerCurve = .continuous
            self.layer?.borderWidth = 1
            self.layer?.borderColor = (dark
                ? NSColor.white.withAlphaComponent(0.22)
                : NSColor.white.withAlphaComponent(0.65)).cgColor
            return
        }
        // Emulation: same tint applied as the blur's background fill.
        self.background.layer?.backgroundColor = fill.cgColor
        self.foreground.layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.white.withAlphaComponent(0.65)).cgColor
    }
    
    fileprivate func setView(_ view: Popup_p?) {
        self.view = view
        
        var isScrollVisible: Bool = false
        var size: NSSize = NSSize(
            width: (view?.frame.width ?? Constants.Popup.width) + (Constants.Popup.margins*2),
            height: (view?.frame.height ?? 0) + Constants.Popup.headerHeight + (Constants.Popup.margins*2) + Constants.Popup.footerHeight
        )
        
        self.windowHeight = NSScreen.main?.visibleFrame.height // for height recalculate when appear/disappear
        self.containerHeight = self.body.documentView?.frame.height // for scroll diff calculation
        if let screenHeight = NSScreen.main?.visibleFrame.height, size.height > screenHeight {
            size.height = screenHeight - Constants.Widget.height
            isScrollVisible = true
        }
        if let screenWidth = NSScreen.main?.visibleFrame.width, size.width > screenWidth {
            size.width = screenWidth
        }
        
        self.setFrameSize(size)
        self.foreground.setFrameSize(size)
        self.background.setFrameSize(size)
        self.body.setFrameSize(NSSize(
            width: size.width - (Constants.Popup.margins*2) + (isScrollVisible ? 20 : 0),
            height: size.height - Constants.Popup.headerHeight - (Constants.Popup.margins*2) - Constants.Popup.footerHeight
        ))
        self.footer.setFrameSize(NSSize(width: size.width - (Constants.Popup.margins*2), height: self.footer.frame.height))
        self.header.setFrameOrigin(NSPoint(x: 0, y: size.height - Constants.Popup.headerHeight))
        
        if let view = view {
            self.body.documentView = view
            view.sizeCallback = { [weak self] size in
                self?.recalculateHeight(size)
            }
        }
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.header.setTitle(newTitle)
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        self.header.setCloseButton(state)
    }
    
    internal func appear() {
        self.view?.appear()
        
        self.display()
        self.body.subviews.first?.display()
        
        if let screenHeight = NSScreen.main?.visibleFrame.height, let size = self.body.documentView?.frame.size {
            if screenHeight != self.windowHeight {
                self.recalculateHeight(size)
            }
        }
        
        if let documentView = self.body.documentView {
            documentView.scroll(NSPoint(x: 0, y: documentView.bounds.size.height))
        }
    }
    internal func disappear() {
        self.header.setCloseButton(false)
        self.view?.disappear()
    }
    
    private func recalculateHeight(_ size: NSSize) {
        var isScrollVisible: Bool = false
        var windowSize: NSSize = NSSize(
            width: size.width + (Constants.Popup.margins*2),
            height: size.height + Constants.Popup.headerHeight + (Constants.Popup.margins*2) + Constants.Popup.footerHeight
        )
        let h0 = self.containerHeight ?? 0
        
        self.windowHeight = NSScreen.main?.visibleFrame.height // for height recalculate when appear/disappear
        self.containerHeight = self.body.documentView?.frame.height // for scroll diff calculation
        if let screenHeight = NSScreen.main?.visibleFrame.height, windowSize.height > screenHeight {
            windowSize.height = screenHeight - Constants.Widget.height
            isScrollVisible = true
        }
        if let screenWidth = NSScreen.main?.visibleFrame.width, windowSize.width > screenWidth {
            windowSize.width = screenWidth
        }
        
        self.window?.setContentSize(windowSize)
        self.foreground.setFrameSize(windowSize)
        self.background.setFrameSize(windowSize)
        self.body.setFrameSize(NSSize(
            width: windowSize.width - (Constants.Popup.margins*2) + (isScrollVisible ? 20 : 0),
            height: windowSize.height - Constants.Popup.headerHeight - (Constants.Popup.margins*2) - Constants.Popup.footerHeight
        ))
        self.footer.setFrameSize(NSSize(width: windowSize.width - (Constants.Popup.margins*2), height: self.footer.frame.height))
        self.header.setFrameOrigin(NSPoint(
            x: self.header.frame.origin.x,
            y: self.body.frame.height + (Constants.Popup.margins*2) + Constants.Popup.footerHeight
        ))
        
        if let documentView = self.body.documentView {
            let diff = h0 - (self.body.documentView?.frame.height ?? 0)
            documentView.scroll(NSPoint(
                x: 0,
                y: self.body.documentVisibleRect.origin.y - (diff < 0 ? diff : 0)
            ))
        }
    }
}

/// The tuning strip at the bottom of every popup: three mini sliders that
/// control how solid each glass layer is (background sheet, bubbles, charts).
/// Values persist and apply live via `.glassLevelsChanged`.
private class GlassTuningView: NSStackView {
    override init(frame: NSRect) {
        super.init(frame: frame)

        self.orientation = .horizontal
        self.distribution = .fillEqually
        self.spacing = 8
        self.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        self.addArrangedSubview(self.group(
            symbol: "macwindow", key: GlassLevels.backgroundKey,
            value: GlassLevels.background, tooltip: "Background glass"
        ))
        self.addArrangedSubview(self.group(
            symbol: "square.stack.3d.up", key: GlassLevels.bubbleKey,
            value: GlassLevels.bubble, tooltip: "Bubble glass"
        ))
        self.addArrangedSubview(self.group(
            symbol: "chart.xyaxis.line", key: GlassLevels.chartKey,
            value: GlassLevels.chart, tooltip: "Chart glass"
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func group(symbol: String, key: String, value: CGFloat, tooltip: String) -> NSStackView {
        let view = NSStackView()
        view.orientation = .horizontal
        view.spacing = 3

        let icon = NSImageView(image: iconFromSymbol(name: symbol, scale: .small))
        icon.contentTintColor = .secondaryLabelColor
        icon.toolTip = localizedString(tooltip)

        let slider = NSSlider(value: Double(value), minValue: 0, maxValue: 1, target: self, action: #selector(self.changed))
        slider.controlSize = .mini
        slider.isContinuous = true
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.toolTip = localizedString(tooltip)

        view.addArrangedSubview(icon)
        view.addArrangedSubview(slider)
        return view
    }

    @objc private func changed(_ sender: NSSlider) {
        guard let key = sender.identifier?.rawValue else { return }
        Store.shared.set(key: key, value: sender.doubleValue)
        NotificationCenter.default.post(name: .glassLevelsChanged, object: nil)
    }
}

/// A soft white gradient falling from the top edge — the specular sheen of
/// light hitting the glass sheet. Non-interactive.
private class SheenView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.gradient.colors = [
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        self.gradient.startPoint = CGPoint(x: 0.5, y: 1)
        self.gradient.endPoint = CGPoint(x: 0.5, y: 0)
        self.layer?.addSublayer(self.gradient)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.gradient.frame = self.bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

internal class HeaderView: NSStackView {
    private var titleView: NSTextField? = nil
    private var activityButton: NSButton?
    
    private var title: String = ""
    private var isCloseAction: Bool = false
    private let activityMonitor: URL?
    private let calendar: URL?
    private var module: ModuleType
    
    init(frame: NSRect, module: ModuleType) {
        self.module = module
        self.activityMonitor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        self.calendar = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        
        super.init(frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height))
        
        self.orientation = .horizontal
        self.distribution = .gravityAreas
        self.spacing = 0
        
        let activity = NSButtonWithPadding()
        activity.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        activity.horizontalPadding = activity.frame.height - 24
        activity.bezelStyle = .regularSquare
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.imageScaling = .scaleNone
        activity.contentTintColor = .secondaryLabelColor
        activity.isBordered = false
        activity.target = self
        activity.focusRingType = .none
        self.activityButton = activity
        self.setupActionButton()
        
        let title = NSTextField(frame: NSRect(x: 0, y: 0, width: frame.width/2, height: 18))
        title.isEditable = false
        title.isSelectable = false
        title.isBezeled = false
        title.wantsLayer = true
        title.textColor = .textColor
        title.backgroundColor = .clear
        title.canDrawSubviewsIntoLayer = true
        title.alignment = .center
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.stringValue = ""
        self.titleView = title
        
        let settings = NSButtonWithPadding()
        settings.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        settings.horizontalPadding = activity.frame.height - 24
        settings.bezelStyle = .regularSquare
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.imageScaling = .scaleNone
        settings.image = iconFromSymbol(name: "command", scale: .large)
        settings.contentTintColor = .secondaryLabelColor
        settings.isBordered = false
        settings.action = #selector(self.openSettings)
        settings.target = self
        settings.toolTip = localizedString("Open module")
        settings.focusRingType = .none
        
        self.addArrangedSubview(activity)
        self.addArrangedSubview(title)
        self.addArrangedSubview(settings)
        
        NSLayoutConstraint.activate([
            title.widthAnchor.constraint(
                equalToConstant: self.frame.width - activity.intrinsicContentSize.width - settings.intrinsicContentSize.width
            )
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.title = newTitle
        self.titleView?.stringValue = localizedString(newTitle)
    }
    
    private func setupActionButton() {
        guard let button = self.activityButton else { return }
        
        if self.isCloseAction {
            button.action = #selector(self.closePopup)
            button.image = iconFromSymbol(name: "xmark.circle.fill", scale: .xlarge)
            button.toolTip = localizedString("Close")
            return
        }
        
        if self.module == .clock {
            button.action = #selector(self.openCalendar)
            button.image = iconFromSymbol(name: "calendar", scale: .large)
            button.toolTip = localizedString("Open Calendar")
            return
        } else if self.module == .remote {
            button.action = #selector(self.openSystemStats)
            button.image = iconFromSymbol(name: "globe", scale: .large)
            button.toolTip = localizedString("Open System Stats")
            return
        }
        
        button.action = #selector(self.openActivityMonitor)
        button.image = iconFromSymbol(name: "chart.bar.fill", scale: .medium)
        button.toolTip = localizedString("Open Activity Monitor")
    }
    
    @objc func openActivityMonitor() {
        guard let app = self.activityMonitor else { return }
        if let tab = self.module.activityMonitorTab {
            UserDefaults(suiteName: "com.apple.ActivityMonitor")?.set(tab, forKey: "SelectedTab")
        }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openCalendar() {
        guard let app = self.calendar else { return }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openSystemStats() {
        guard let url = URL(string: "https://app.system-stats.com") else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": self.title])
    }
    
    @objc private func closePopup() {
        self.window?.setIsVisible(false)
        self.setCloseButton(false)
        return
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        guard state != self.isCloseAction else { return }
        self.isCloseAction = state
        self.setupActionButton()
    }
}
