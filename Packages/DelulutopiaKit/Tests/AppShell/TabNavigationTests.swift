@testable import AppShell
import CoreGraphics
import DLData
import DLUI
import Testing

/// iPad Layout §5–§7: routing and selection per layout, and the orientation rule (IP11).
@Suite("Tab navigation")
struct TabNavigationTests {
    // MARK: Layout

    @Test("Layout: regular width is the split on iPad and the wide phone on the Duo")
    func layoutResolution() {
        #expect(AppLayout.resolve(pad: false, regularWidth: false) == .phone)
        #expect(AppLayout.resolve(pad: true, regularWidth: false) == .phone)
        #expect(AppLayout.resolve(pad: true, regularWidth: true) == .split)
        #expect(AppLayout.resolve(pad: false, regularWidth: true) == .widePhone)
        #expect(AppLayout.phone.readableWidth == nil)
        #expect(AppLayout.split.readableWidth == 660)
        #expect(AppLayout.widePhone.readableWidth == 680)
    }

    // MARK: iPhone (unchanged behaviour)

    @Test("Phone: open pushes on the current tab, replace swaps the top, selectTab clears")
    func phoneStacks() {
        var nav = TabNavigation(layout: .phone, selected: .emails)
        nav.open(.newEmail)
        #expect(nav.path(.emails) == [.newEmail])
        nav.replace(.thread("t1"))
        #expect(nav.path(.emails) == [.thread("t1")])
        nav.open(.friend)
        #expect(nav.path(.emails) == [.thread("t1"), .friend])
        nav.selectTab(.letters)
        #expect(nav.selected == .letters)
        #expect(nav.path(.letters).isEmpty)
        #expect(nav.path(.emails) == [.thread("t1"), .friend])
        #expect(nav.selections.isEmpty)
        #expect(nav.cover == nil)
    }

    @Test("Phone: Home pushes on Home (no tab switch); Write is pushed, not a cover")
    func phoneHome() {
        var nav = TabNavigation(layout: .phone, selected: .home)
        nav.open(.letter("l1"))
        nav.open(.write(replyTo: "l1"))
        #expect(nav.selected == .home)
        #expect(nav.path(.home) == [.letter("l1"), .write(replyTo: "l1")])
        #expect(nav.cover == nil)
    }

    @Test("Phone: re-tapping the tab pops to its root")
    func phoneRetap() {
        var nav = TabNavigation(layout: .phone, selected: .letters)
        nav.open(.letter("l1"))
        nav.tapTab(.emails)
        #expect(nav.path(.letters) == [.letter("l1")])
        nav.tapTab(.letters)
        nav.tapTab(.letters)
        #expect(nav.path(.letters).isEmpty)
    }

    @Test("Phone: a link opens its screen over the tab's root")
    func phoneLinks() {
        var nav = TabNavigation(layout: .phone, selected: .home)
        nav.open(link: .thread("t9"))
        #expect(nav.selected == .emails)
        #expect(nav.path(.emails) == [.thread("t9")])
        nav.open(link: .notificationSettings)
        #expect(nav.selected == .you)
        #expect(nav.path(.you) == [.notifications])
        nav.open(link: .discussions)
        #expect(nav.selected == .discussions)
        #expect(nav.path(.discussions).isEmpty)
    }

    // MARK: iPad split

    @Test("Split: a list row selects into the detail column; pages push over it there")
    func splitSelect() {
        var nav = TabNavigation(layout: .split, selected: .emails)
        nav.open(.thread("t1"))
        #expect(nav.selection(.emails) == .thread("t1"))
        #expect(nav.path(.emails).isEmpty)
        nav.open(.friend)
        #expect(nav.path(.emails) == [.friend])
        nav.open(.thread("t2"))
        #expect(nav.selection(.emails) == .thread("t2"))
        #expect(nav.path(.emails).isEmpty)
    }

    @Test("Split: nothing is selected by itself, except You's Profile (IP4)")
    func splitDefaults() {
        let nav = TabNavigation(layout: .split, selected: .letters)
        #expect(nav.selection(.letters) == nil)
        #expect(nav.selection(.discussions) == nil)
        #expect(nav.selection(.emails) == nil)
        #expect(nav.selection(.you) == .profile)
    }

    @Test("Split: New email fills the detail, then becomes its thread after Send (IP6)")
    func splitNewEmail() {
        var nav = TabNavigation(layout: .split, selected: .emails)
        nav.open(.newEmail)
        #expect(nav.selection(.emails) == .newEmail)
        nav.replace(.thread("t3"))
        #expect(nav.selection(.emails) == .thread("t3"))
        #expect(nav.path(.emails).isEmpty)
    }

    @Test("Split: a new discussion fills the detail; editing one is pushed over it")
    func splitCompose() {
        var nav = TabNavigation(layout: .split, selected: .discussions)
        nav.open(.composeDiscussion(editId: nil))
        #expect(nav.selection(.discussions) == .composeDiscussion(editId: nil))
        nav.closeDetail(.discussions)
        #expect(nav.selection(.discussions) == nil)
        nav.open(.discussion("d1"))
        nav.open(.composeDiscussion(editId: "d1"))
        #expect(nav.selection(.discussions) == .discussion("d1"))
        #expect(nav.path(.discussions) == [.composeDiscussion(editId: "d1")])
    }

    @Test("Split: Archived shows in the list column")
    func splitArchived() {
        var nav = TabNavigation(layout: .split, selected: .discussions)
        nav.open(.archived)
        #expect(nav.archivedList)
        #expect(nav.selection(.discussions) == nil)
        nav.tapTab(.discussions)
        #expect(!nav.archivedList)
    }

    @Test("Split: Write opens as a cover; sending lands on Letters with the cover closed")
    func splitWrite() {
        var nav = TabNavigation(layout: .split, selected: .letters)
        nav.open(.letter("l1"))
        nav.open(.write(replyTo: "l1"))
        #expect(nav.cover == .write(replyTo: "l1"))
        #expect(nav.selection(.letters) == .letter("l1"))
        nav.selectTab(.letters)
        #expect(nav.cover == nil)
        #expect(nav.selection(.letters) == nil)
    }

    @Test("Split: Home opens a letter on Letters, selected (IP3)")
    func splitFromHome() {
        var nav = TabNavigation(layout: .split, selected: .home)
        nav.open(.letter("l5"))
        #expect(nav.selected == .letters)
        #expect(nav.selection(.letters) == .letter("l5"))
        #expect(nav.path(.home).isEmpty)
        nav.selected = .home
        nav.open(.friend)
        #expect(nav.selected == .you)
        #expect(nav.selection(.you) == .friend)
    }

    @Test("Split: links (push taps, notices) select in the right column")
    func splitLinks() {
        var nav = TabNavigation(layout: .split, selected: .home)
        nav.open(link: .letter("l7"))
        #expect(nav.selected == .letters)
        #expect(nav.selection(.letters) == .letter("l7"))
        nav.open(link: .discussion("d2"))
        #expect(nav.selection(.discussions) == .discussion("d2"))
        nav.open(link: .thread("t4"))
        #expect(nav.selected == .emails)
        #expect(nav.selection(.emails) == .thread("t4"))
        nav.open(link: .notificationSettings)
        #expect(nav.selection(.you) == .notifications)
        nav.open(link: .emails)
        #expect(nav.selection(.emails) == nil)
    }

    @Test("Split: the detail column closes to the hint")
    func splitClose() {
        var nav = TabNavigation(layout: .split, selected: .discussions)
        nav.open(.discussion("d1"))
        nav.open(.friend)
        nav.closeDetail(.discussions)
        #expect(nav.selection(.discussions) == nil)
        #expect(nav.path(.discussions).isEmpty)
    }

    // MARK: Changing layout (§6)

    @Test("Relayout: split → phone puts each selection under its pushed pages, Write on top")
    func collapse() {
        var nav = TabNavigation(layout: .split, selected: .letters)
        nav.open(.letter("l1"))
        nav.open(.write(replyTo: "l1"))
        nav.selected = .discussions
        nav.open(.archived)
        nav.open(.discussion("d1"))
        nav.open(.friend)
        nav.relayout(.phone)
        #expect(nav.layout == .phone)
        #expect(nav.path(.letters) == [.letter("l1"), .write(replyTo: "l1")])
        #expect(nav.path(.discussions) == [.archived, .discussion("d1"), .friend])
        #expect(nav.selected == .letters)
        #expect(nav.selections.isEmpty)
        #expect(nav.cover == nil)
        #expect(!nav.archivedList)
    }

    @Test("Relayout: phone → split selects the first route and keeps the rest pushed")
    func expand() {
        var nav = TabNavigation(layout: .phone, selected: .emails)
        nav.open(.thread("t1"))
        nav.open(.friend)
        nav.selected = .letters
        nav.open(.letter("l1"))
        nav.open(.write(replyTo: "l1"))
        nav.selected = .discussions
        nav.open(.archived)
        nav.relayout(.split)
        #expect(nav.selection(.emails) == .thread("t1"))
        #expect(nav.path(.emails) == [.friend])
        #expect(nav.selection(.letters) == .letter("l1"))
        #expect(nav.path(.letters).isEmpty)
        #expect(nav.cover == .write(replyTo: "l1"))
        #expect(nav.archivedList)
    }

    @Test("Relayout: round trip keeps what was open")
    func roundTrip() {
        var nav = TabNavigation(layout: .phone, selected: .emails)
        nav.open(.thread("t1"))
        nav.open(.friend)
        nav.relayout(.split)
        nav.relayout(.phone)
        #expect(nav.path(.emails) == [.thread("t1"), .friend])
    }

    @Test("Relayout: phone ↔ wide phone changes nothing")
    func widePhone() {
        var nav = TabNavigation(layout: .phone, selected: .letters)
        nav.open(.letter("l1"))
        nav.relayout(.widePhone)
        #expect(nav.path(.letters) == [.letter("l1")])
        nav.open(.write(replyTo: "l1"))
        #expect(nav.cover == nil)
        #expect(nav.path(.letters) == [.letter("l1"), .write(replyTo: "l1")])
    }

    // MARK: Orientation (IP11)

    @Test("Orientation: standard iPhones stay portrait; the Duo's inner display and iPads turn")
    func orientation() {
        let iphones: [CGSize] = [
            CGSize(width: 375, height: 667), CGSize(width: 375, height: 812), CGSize(width: 390, height: 844),
            CGSize(width: 393, height: 852), CGSize(width: 402, height: 874), CGSize(width: 414, height: 896),
            CGSize(width: 428, height: 926), CGSize(width: 430, height: 932), CGSize(width: 440, height: 956),
            CGSize(width: 420, height: 912), .zero,
            CGSize(width: 466, height: 678), // the Duo's cover display

        ]
        for size in iphones {
            #expect(OrientationRule.allowed(pad: false, screen: size) == .portrait)
            #expect(OrientationRule.allowed(pad: false, screen: CGSize(width: size.height, height: size.width)) == .portrait)
        }
        #expect(OrientationRule.allowed(pad: false, screen: CGSize(width: 669, height: 951)) == .allButUpsideDown)
        #expect(OrientationRule.allowed(pad: false, screen: CGSize(width: 1010, height: 716)) == .allButUpsideDown)
        #expect(OrientationRule.allowed(pad: false, screen: CGSize(width: 716, height: 1010)) == .allButUpsideDown)
        #expect(OrientationRule.allowed(pad: true, screen: CGSize(width: 1032, height: 1376)) == .all)
        #expect(OrientationRule.allowed(pad: true, screen: CGSize(width: 320, height: 480)) == .all)
    }

    // MARK: Routes

    @Test("Each route belongs to a tab")
    func routeTabs() {
        #expect(AppRoute.letter("x").tab == .letters)
        #expect(AppRoute.write().tab == .letters)
        #expect(AppRoute.archived.tab == .discussions)
        #expect(AppRoute.newEmail.tab == .emails)
        #expect(AppRoute.language.tab == .you)
    }
}
