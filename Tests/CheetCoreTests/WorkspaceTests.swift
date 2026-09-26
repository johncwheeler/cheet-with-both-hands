import CoreGraphics
import Foundation
import Testing
@testable import CheetCore

struct WorkspaceTests {
    let git = UUID(), vim = UUID(), tmux = UUID()

    func window(_ id: UUID, display: String? = "DISPLAY-A") -> WorkspaceWindow {
        WorkspaceWindow(cheetID: id, frame: NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5), displayID: display)
    }

    @Test func roundTripsThroughJSON() throws {
        // Whole-second dates: the library's ISO-8601 dates drop fractions of a second.
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        let workspace = Workspace(name: "Coding", windows: [window(git), window(vim)],
                                  hotkey: KeyCombo(keyCode: KeyCodes.one, modifiers: [.control, .option]),
                                  createdAt: saved, updatedAt: saved)
        let data = try JSONEncoder.cheet.encode(workspace)
        #expect(try JSONDecoder.cheet.decode(Workspace.self, from: data) == workspace)
    }

    @Test func decodesWithMissingOrBrokenFields() throws {
        let json = #"{"name":"Old","windows":[{"cheetID":"\#(git.uuidString)","frame":{"x":0,"y":0,"width":0.5,"height":0.5}}],"hotkey":"nonsense"}"#
        let workspace = try JSONDecoder.cheet.decode(Workspace.self, from: Data(json.utf8))
        #expect(workspace.name == "Old")
        #expect(workspace.windows.map(\.cheetID) == [git])
        #expect(workspace.windows[0].displayID == nil)
        #expect(workspace.hotkey == nil)
    }

    @Test func pruningDropsDeletedCheets() {
        let workspace = Workspace(name: "W", windows: [window(git), window(vim), window(tmux)])
        #expect(workspace.pruned(keeping: [git, tmux]).windows.map(\.cheetID) == [git, tmux])
    }

    @Test func suggestedNames() {
        #expect(Workspace.suggestedName(for: []) == "Workspace")
        #expect(Workspace.suggestedName(for: ["Git"]) == "Git")
        #expect(Workspace.suggestedName(for: ["Git", "Vim"]) == "Git + Vim")
        #expect(Workspace.suggestedName(for: ["Git", "Vim", "tmux", "Zsh", "Go"]) == "Git + Vim + tmux + 2 more")
    }

    @Test func restoresOnItsOwnDisplayWhenConnected() {
        let a = ScreenInfo(displayID: "DISPLAY-A", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let b = ScreenInfo(displayID: "DISPLAY-B", visibleFrame: CGRect(x: 1000, y: 0, width: 2000, height: 1000))
        let frame = window(git, display: "DISPLAY-B").restoredFrame(on: [a, b], fallback: a, minSize: CGSize(width: 360, height: 220))
        #expect(frame == CGRect(x: 1200, y: 200, width: 800, height: 500))
    }

    @Test func missingDisplayFallsBackInsideTheFallbackScreen() {
        let a = ScreenInfo(displayID: "DISPLAY-A", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let frame = window(git, display: "UNPLUGGED").restoredFrame(on: [a], fallback: a, minSize: CGSize(width: 360, height: 220))
        #expect(frame == CGRect(x: 100, y: 160, width: 400, height: 400))
        #expect(a.visibleFrame.contains(frame))
    }

    @Test func clampingKeepsARectInsideItsContainerAndAboveMinimumSize() {
        let container = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(CGRect(x: 900, y: -50, width: 300, height: 100).clamped(to: container, minSize: CGSize(width: 360, height: 220))
                == CGRect(x: 640, y: 0, width: 360, height: 220))
        #expect(CGRect(x: -10, y: 10, width: 2000, height: 100).clamped(to: container, minSize: .zero)
                == CGRect(x: 0, y: 10, width: 1000, height: 100))
    }
}

struct LibraryFileTests {
    @Test func libraryWithWorkspacesRoundTrips() throws {
        let cheet = Cheet(title: "Git", sections: [], createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                          updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let workspace = Workspace(name: "Coding", windows: [WorkspaceWindow(cheetID: cheet.id, frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1), displayID: nil)],
                                  createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let library = Library(cheets: [cheet], workspaces: [workspace])
        let data = try LibraryStore.encodeLibrary(library)
        #expect(String(decoding: data, as: UTF8.self).contains("\"version\" : 2"))
        #expect(try LibraryStore.decodeLibrary(from: data) == library)
    }

    @Test func versionOneFilesLoadWithNoWorkspaces() throws {
        let json = #"{"version":1,"cheets":[{"title":"Old","sections":[]}]}"#
        let library = try LibraryStore.decodeLibrary(from: Data(json.utf8))
        #expect(library.cheets.map(\.title) == ["Old"])
        #expect(library.workspaces.isEmpty)
    }

    @Test func unreadableWorkspacesDoNotLoseTheCheets() throws {
        let json = #"{"version":2,"cheets":[{"title":"Keep","sections":[]}],"workspaces":"garbage"}"#
        let library = try LibraryStore.decodeLibrary(from: Data(json.utf8))
        #expect(library.cheets.map(\.title) == ["Keep"])
        #expect(library.workspaces.isEmpty)
    }

    @Test func bareArraysAndSingleCheetsStillImport() throws {
        let single = try LibraryStore.decodeLibrary(from: Data(#"{"title":"One","sections":[]}"#.utf8))
        #expect(single.cheets.map(\.title) == ["One"])
        let array = try LibraryStore.decodeLibrary(from: Data(#"[{"title":"A","sections":[]},{"title":"B","sections":[]}]"#.utf8))
        #expect(array.cheets.map(\.title) == ["A", "B"])
    }
}
