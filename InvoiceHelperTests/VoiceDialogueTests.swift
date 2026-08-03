import XCTest
@testable import InvoiceHelper

/// Covers the deterministic core: slot sequencing, skip and revisit, and parsing.
///
/// This layer is pure logic over plain data, with no audio, UI or I/O, which is why
/// the dialogue manager was built on slots rather than words. The speech layer
/// (endpointing, synthesis sequencing, barge-in) is not testable here and only
/// reveals its behaviour on hardware.
@MainActor
final class VoiceDialogueTests: XCTestCase {

    private func makeManager(customers: [(String, String)] = [("c1", "Acme Ltd")]) -> DialogueManager {
        DialogueManager(
            draft: InvoiceDraft(),
            resolveCustomer: { spoken in
                customers.first { $0.1.lowercased() == spoken.lowercased() }
                    .map { (id: $0.0, name: $0.1) }
            }
        )
    }

    // MARK: - Slot ordering

    func testStartsByAskingForCustomer() {
        let manager = makeManager()
        _ = manager.opening()
        XCTAssertEqual(manager.focusedSlot, .customer)
        XCTAssertEqual(manager.draft.nextGap, .slot(.customer))
    }

    func testAdvancesCustomerToDescriptionToQuantityToPrice() {
        let manager = makeManager()
        _ = manager.opening()

        _ = manager.handle(.setCustomer("Acme Ltd"))
        XCTAssertEqual(manager.draft.nextGap, .slot(.itemDescription(0)))

        _ = manager.handle(.itemDescription("Rewiring"))
        XCTAssertEqual(manager.draft.nextGap, .slot(.itemQuantity(0)))

        _ = manager.handle(.quantity(3))
        XCTAssertEqual(manager.draft.nextGap, .slot(.itemPrice(0)))

        _ = manager.handle(.price(50))
        XCTAssertEqual(manager.draft.nextGap, .anythingElse)
    }

    func testTaxIsAskedLastAndOnlyOnce() {
        let manager = makeManager()
        _ = manager.opening()
        _ = manager.handle(.setCustomer("Acme Ltd"))
        _ = manager.handle(.fullItem(description: "Rewiring", quantity: 3, price: 50))
        _ = manager.handle(.noMoreItems)

        XCTAssertEqual(manager.draft.nextGap, .slot(.taxRate))
        _ = manager.handle(.confirmTax)
        XCTAssertEqual(manager.draft.nextGap, .readyToConfirm)
        XCTAssertEqual(manager.draft.taxRate, 20)
    }

    // MARK: - Skip and revisit

    func testSkippedDescriptionIsRevisitedAfterOtherSlots() {
        let manager = makeManager()
        _ = manager.opening()
        _ = manager.handle(.setCustomer("Acme Ltd"))

        _ = manager.handle(.skip)
        XCTAssertEqual(manager.draft.state(of: .itemDescription(0)), .skipped)

        // Moves on rather than re-asking the same thing.
        XCTAssertNotEqual(manager.draft.nextGap, .slot(.itemDescription(0)))

        _ = manager.handle(.quantity(2))
        _ = manager.handle(.price(40))

        // Comes back to it once nothing is empty.
        XCTAssertEqual(manager.draft.nextGap, .slot(.itemDescription(0)))
    }

    func testSkippingTwiceStopsAsking() {
        let manager = makeManager()
        _ = manager.opening()
        _ = manager.handle(.setCustomer("Acme Ltd"))
        _ = manager.handle(.skip)
        _ = manager.handle(.quantity(2))
        _ = manager.handle(.price(40))

        XCTAssertEqual(manager.draft.nextGap, .slot(.itemDescription(0)))
        _ = manager.handle(.skip)

        XCTAssertEqual(manager.draft.state(of: .itemDescription(0)), .skippedFinal)
        XCTAssertNotEqual(manager.draft.nextGap, .slot(.itemDescription(0)))
    }

    func testSkippedQuantityDefaultsToOneAndIsMarkedAssumed() {
        let manager = makeManager()
        _ = manager.opening()
        _ = manager.handle(.setCustomer("Acme Ltd"))
        _ = manager.handle(.itemDescription("Callout"))
        _ = manager.handle(.skip)

        XCTAssertEqual(manager.draft.items[0].quantity, 1)
        XCTAssertEqual(manager.draft.state(of: .itemQuantity(0)), .assumed)
        // Never revisited, because it now has a value.
        XCTAssertNotEqual(manager.draft.nextGap, .slot(.itemQuantity(0)))
    }

    func testFillingASkippedSlotClearsTheSkip() {
        let manager = makeManager()
        _ = manager.opening()
        _ = manager.handle(.setCustomer("Acme Ltd"))
        _ = manager.handle(.skip)
        XCTAssertEqual(manager.draft.state(of: .itemDescription(0)), .skipped)

        manager.focus(.itemDescription(0))
        _ = manager.handle(.itemDescription("Rewiring"))
        XCTAssertEqual(manager.draft.state(of: .itemDescription(0)), .filled)
    }

    // MARK: - Saving

    func testCannotSaveWithoutCustomer() {
        let draft = InvoiceDraft()
        draft.setDescription("Rewiring", at: 0)
        draft.setQuantity(2, at: 0)
        draft.setUnitPrice(50, at: 0)

        XCTAssertFalse(draft.canSave)
        XCTAssertNotNil(draft.saveBlockedReason)
    }

    func testCannotSaveWithoutACompleteItem() {
        let draft = InvoiceDraft()
        draft.setCustomer(id: "c1", name: "Acme Ltd")
        draft.setDescription("Rewiring", at: 0)

        XCTAssertFalse(draft.canSave)
    }

    func testFinishBeforeReadyDoesNotConfirm() {
        let manager = makeManager()
        _ = manager.opening()
        _ = manager.handle(.finish)
        XCTAssertFalse(manager.isAwaitingConfirmation)
    }

    func testTotalsUseTaxRate() {
        let draft = InvoiceDraft()
        draft.setCustomer(id: "c1", name: "Acme Ltd")
        draft.setDescription("Rewiring", at: 0)
        draft.setQuantity(2, at: 0)
        draft.setUnitPrice(50, at: 0)
        draft.setTaxRate(20)

        XCTAssertEqual(draft.subtotal, 100, accuracy: 0.001)
        XCTAssertEqual(draft.tax, 20, accuracy: 0.001)
        XCTAssertEqual(draft.total, 120, accuracy: 0.001)
    }

    // MARK: - Focus routing

    func testBareValueLandsOnTheFocusedItem() {
        let manager = makeManager()
        _ = manager.opening()
        _ = manager.handle(.setCustomer("Acme Ltd"))
        _ = manager.handle(.fullItem(description: "Rewiring", quantity: 2, price: 50))
        _ = manager.handle(.itemDescription("Second fix"))

        // User taps back to item one's price, then speaks.
        manager.focus(.itemPrice(0))
        _ = manager.handle(.price(75))

        XCTAssertEqual(manager.draft.items[0].unitPrice, 75)
        XCTAssertNotEqual(manager.draft.items[1].unitPrice, 75)
    }

    // MARK: - Quiet mode

    func testStaysVocalForOneOrTwoManualFills() {
        let manager = makeManager()
        _ = manager.opening()

        manager.draft.setCustomer(id: "c1", name: "Acme Ltd")
        XCTAssertNotNil(manager.recordManualFill(of: .customer))
        XCTAssertFalse(manager.isQuiet)

        manager.draft.setDescription("Rewiring", at: 0)
        XCTAssertNotNil(manager.recordManualFill(of: .itemDescription(0)))
        XCTAssertFalse(manager.isQuiet)
    }

    func testGoesQuietAfterThreeManualFills() {
        let manager = makeManager()
        _ = manager.opening()

        manager.draft.setCustomer(id: "c1", name: "Acme Ltd")
        _ = manager.recordManualFill(of: .customer)
        manager.draft.setDescription("Rewiring", at: 0)
        _ = manager.recordManualFill(of: .itemDescription(0))
        manager.draft.setQuantity(2, at: 0)

        XCTAssertNil(manager.recordManualFill(of: .itemQuantity(0)),
                     "Third manual fill should return no line to speak")
        XCTAssertTrue(manager.isQuiet)
    }

    func testKeepsFollowingFocusWhileQuiet() {
        let manager = makeManager()
        _ = manager.opening()

        manager.draft.setCustomer(id: "c1", name: "Acme Ltd")
        _ = manager.recordManualFill(of: .customer)
        manager.draft.setDescription("Rewiring", at: 0)
        _ = manager.recordManualFill(of: .itemDescription(0))
        manager.draft.setQuantity(2, at: 0)
        _ = manager.recordManualFill(of: .itemQuantity(0))

        // Quiet means silent, not inert: focus still advances to the next gap.
        XCTAssertTrue(manager.isQuiet)
        XCTAssertEqual(manager.focusedSlot, .itemPrice(0))
    }

    func testSpeakingBreaksTheQuietSpell() {
        let manager = makeManager()
        _ = manager.opening()

        manager.draft.setCustomer(id: "c1", name: "Acme Ltd")
        _ = manager.recordManualFill(of: .customer)
        manager.draft.setDescription("Rewiring", at: 0)
        _ = manager.recordManualFill(of: .itemDescription(0))
        manager.draft.setQuantity(2, at: 0)
        _ = manager.recordManualFill(of: .itemQuantity(0))
        XCTAssertTrue(manager.isQuiet)

        XCTAssertNotNil(manager.handle(.price(50)))
        XCTAssertFalse(manager.isQuiet)
    }

    func testManualStreakResetsSoQuietNeedsThreeMoreFills() {
        let manager = makeManager()
        _ = manager.opening()

        manager.draft.setCustomer(id: "c1", name: "Acme Ltd")
        _ = manager.recordManualFill(of: .customer)
        manager.draft.setDescription("Rewiring", at: 0)
        _ = manager.recordManualFill(of: .itemDescription(0))

        // A spoken answer in the middle clears the streak.
        _ = manager.handle(.quantity(2))

        manager.draft.setUnitPrice(50, at: 0)
        XCTAssertNotNil(manager.recordManualFill(of: .itemPrice(0)))
        XCTAssertFalse(manager.isQuiet, "Streak should have restarted at one")
    }

    func testResumeSpeakingUnmutesWithoutSpokenInput() {
        let manager = makeManager()
        _ = manager.opening()

        manager.draft.setCustomer(id: "c1", name: "Acme Ltd")
        _ = manager.recordManualFill(of: .customer)
        manager.draft.setDescription("Rewiring", at: 0)
        _ = manager.recordManualFill(of: .itemDescription(0))
        manager.draft.setQuantity(2, at: 0)
        _ = manager.recordManualFill(of: .itemQuantity(0))
        XCTAssertTrue(manager.isQuiet)

        manager.resumeSpeaking()
        XCTAssertFalse(manager.isQuiet)
    }

    func testAnEmptyFieldIsNotAManualFill() {
        let manager = makeManager()
        _ = manager.opening()

        // Tapping into a field and leaving without typing must not count, or
        // browsing the form would silence the app.
        XCTAssertNil(manager.recordManualFill(of: .itemDescription(0)))
        XCTAssertFalse(manager.isQuiet)
    }

    // MARK: - Parsing

    func testParsesBareNumberAsQuantityWhenAsked() {
        let parser = SlotParser()
        let intent = parser.parse("three", gap: .slot(.itemQuantity(0)), isConfirming: false)
        XCTAssertEqual(intent, .quantity(3))
    }

    func testParsesCompoundNumberWords() {
        let parser = SlotParser()
        XCTAssertEqual(parser.parse("twenty five", gap: .slot(.itemPrice(0)), isConfirming: false), .price(25))
    }

    func testParsesWholeItemInOneBreath() {
        let parser = SlotParser()
        let intent = parser.parse("two hours of joinery at forty",
                                  gap: .slot(.itemDescription(0)), isConfirming: false)
        guard case .fullItem(let description, let quantity, let price) = intent else {
            return XCTFail("Expected a full item, got \(intent)")
        }
        XCTAssertEqual(quantity, 2)
        XCTAssertEqual(price, 40)
        XCTAssertTrue(description.lowercased().contains("joinery"))
    }

    func testRecognisesSkipVocabulary() {
        let parser = SlotParser()
        for phrase in ["skip", "leave it", "not sure yet"] {
            XCTAssertEqual(parser.parse(phrase, gap: .slot(.itemPrice(0)), isConfirming: false), .skip,
                           "Expected \(phrase) to be a skip")
        }
    }

    func testYesAtTaxSlotConfirmsRatherThanAnswering() {
        let parser = SlotParser()
        XCTAssertEqual(parser.parse("yes", gap: .slot(.taxRate), isConfirming: false), .confirmTax)
        XCTAssertEqual(parser.parse("make it five", gap: .slot(.taxRate), isConfirming: false), .setTax(5))
    }

    func testStopIsCancelNotCorrection() {
        let parser = SlotParser()
        XCTAssertEqual(parser.parse("stop", gap: .slot(.itemPrice(0)), isConfirming: false), .cancel)
    }

    func testNoMoreItemsEndsTheItemLoop() {
        let parser = SlotParser()
        XCTAssertEqual(parser.parse("that's it", gap: .anythingElse, isConfirming: false), .noMoreItems)
    }
}
