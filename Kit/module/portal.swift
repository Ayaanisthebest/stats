//
//  portal.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 17/02/2023
//  Using Swift 5.0
//  Running on macOS 13.2
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public protocol Portal_p: NSView {
    var name: String { get }
}

open class PortalWrapper: NSStackView, Portal_p {
    public var name: String
    private let header: PortalHeader
    private var glassEffect: NSView? = nil

    public init(_ type: ModuleType, height: CGFloat = Constants.Popup.portalHeight) {
        self.name = type.stringValue
        self.header = PortalHeader(type.stringValue)

        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: height))

        self.wantsLayer = true
        if #available(macOS 26.0, *) {
            self.layer?.cornerRadius = Constants.Popup.cardRadius
            self.layer?.cornerCurve = .continuous
            // The card IS a real Liquid Glass element floating on the opaque
            // sheet; content stays above as siblings (click-safe — the bug
            // was window-server-level, fixed by the popup's event backstop).
            let glass = NSGlassEffectView(frame: self.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = Constants.Popup.cardRadius
            // `.clear` = maximum refraction/lensing for the bubbles.
            glass.style = .clear
            self.glassEffect = glass
            self.addSubview(glass, positioned: .below, relativeTo: nil)
            // Bright hairline edge + floating shadow so the glass card
            // visibly pops off the sheet behind it.
            self.layer?.borderWidth = 1
            self.layer?.masksToBounds = false
            self.layer?.shadowColor = NSColor.black.cgColor
            self.layer?.shadowOffset = NSSize(width: 0, height: -2)
            self.layer?.shadowRadius = 6
        } else {
            self.layer?.cornerRadius = 3
        }
        self.applyCardStyle()
        
        self.orientation = .vertical
        self.distribution = .fillEqually
        self.spacing = Constants.Popup.spacing*2
        self.edgeInsets = NSEdgeInsets(
            top: Constants.Popup.spacing*2,
            left: Constants.Popup.spacing*2,
            bottom: Constants.Popup.spacing*2,
            right: Constants.Popup.spacing*2
        )
        self.addArrangedSubview(self.header)

        self.load()

        self.heightAnchor.constraint(equalToConstant: Constants.Popup.portalHeight).isActive = true

        NotificationCenter.default.addObserver(self, selector: #selector(self.glassLevelsChanged), name: .glassLevelsChanged, object: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .glassLevelsChanged, object: nil)
    }

    @objc private func glassLevelsChanged() {
        self.applyCardStyle()
    }
    
    public override func updateLayer() {
        self.applyCardStyle()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.applyCardStyle()
    }

    /// Matte card floating on the popup's Liquid Glass sheet (macOS 26+);
    /// solid system background on older systems.
    private func applyCardStyle() {
        if #available(macOS 26.0, *) {
            // Real glass: the bubble slider drives the glass tint; the
            // hairline + shadow make the card pop off the sheet.
            let dark = self.isDarkModeEffective
            (self.glassEffect as? NSGlassEffectView)?.tintColor = GlassLevels.fill(.bubble, dark: dark)
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.layer?.borderColor = (dark
                ? NSColor.white.withAlphaComponent(0.28)
                : NSColor.white.withAlphaComponent(0.75)).cgColor
            self.layer?.shadowOpacity = dark ? 0.3 : 0.15
        } else {
            self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
    
    open func load() {
        self.addArrangedSubview(NSView())
    }
}

public class PortalHeader: NSStackView {
    private let name: String
    
    public init(_ name: String) {
        self.name = name
        
        super.init(frame: NSRect.zero)
        self.heightAnchor.constraint(equalToConstant: 20).isActive = true
        
        let title = NSTextField()
        title.isEditable = false
        title.isSelectable = false
        title.isBezeled = false
        title.wantsLayer = true
        title.textColor = .textColor
        title.backgroundColor = .clear
        title.canDrawSubviewsIntoLayer = true
        title.alignment = .center
        title.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        title.stringValue = localizedString(name)
        
        let settings = NSButton()
        settings.heightAnchor.constraint(equalToConstant: 18).isActive = true
        settings.bezelStyle = .regularSquare
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.imageScaling = .scaleProportionallyDown
        settings.image = iconFromSymbol(name: "gearshape.fill", scale: .xlarge)
        settings.contentTintColor = .secondaryLabelColor
        settings.isBordered = false
        settings.action = #selector(self.openSettings)
        settings.target = self
        settings.toolTip = localizedString("Open module settings")
        settings.focusRingType = .none
        
        self.addArrangedSubview(title)
        self.addArrangedSubview(NSView())
        self.addArrangedSubview(settings)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func openSettings() {
        self.window?.setIsVisible(false)
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": self.name])
    }
}
