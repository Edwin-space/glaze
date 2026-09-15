import Testing
@testable import GlazeBooks
@testable import GlazeCore

@Suite("Two pages at a time, with the cover on its own")
struct ComicSpreadsTests {
    @Test("One page per screen when spreads are off")
    func single() {
        let spreads = ComicSpreads(pageCount: 5, isDouble: false)
        #expect(spreads.count == 5)
        #expect(spreads.pages(at: 3) == [3])
        #expect(spreads.index(containing: 3) == 3)
    }

    /// The pairing that matters: 1 with 2, not 0 with 1. Getting this wrong shifts
    /// every spread by one and splits the artwork down the middle.
    @Test("The cover stands alone and the rest pair up behind it")
    func doubled() {
        let spreads = ComicSpreads(pageCount: 7, isDouble: true)
        #expect(spreads.pages(at: 0) == [0])
        #expect(spreads.pages(at: 1) == [1, 2])
        #expect(spreads.pages(at: 2) == [3, 4])
        #expect(spreads.pages(at: 3) == [5, 6])
        #expect(spreads.count == 4)
    }

    @Test("A last page with no partner shows on its own")
    func oddTail() {
        let spreads = ComicSpreads(pageCount: 6, isDouble: true)
        #expect(spreads.pages(at: 3) == [5])
        #expect(spreads.count == 4)
    }

    @Test("A page can be found again after the layout changes")
    func roundTrip() {
        let spreads = ComicSpreads(pageCount: 20, isDouble: true)
        for page in 0..<20 {
            #expect(spreads.pages(at: spreads.index(containing: page)).contains(page))
        }
    }
}
