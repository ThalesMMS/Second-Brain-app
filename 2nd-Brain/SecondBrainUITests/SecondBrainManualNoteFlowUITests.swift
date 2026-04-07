import XCTest

final class SecondBrainManualNoteFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_emptyState_manualNoteLifecycle_handlesFullLifecycle() throws {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()
        app.launch()

        let createdTitle = "UI Test Manual Note"
        let createdBody = "Created in deterministic UI test mode."
        let updatedTitle = "UI Test Edited Note"
        let appendedBody = "Edited in note detail."

        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5))

        openQuickCapture(in: app)
        saveTextNote(in: app, title: createdTitle, body: createdBody)

        let createdNoteRow = app.staticTexts[createdTitle]
        XCTAssertTrue(createdNoteRow.waitForExistence(timeout: 5))
        createdNoteRow.tap()

        let noteTitleField = app.textFields["noteTitleField"]
        XCTAssertTrue(noteTitleField.waitForExistence(timeout: 5))
        XCTAssertEqual(noteTitleField.stringValue, createdTitle)

        replaceText(in: noteTitleField, with: updatedTitle)
        let noteBodyEditor = app.textViews["noteBodyEditor"]
        appendTextToEditor(noteBodyEditor, text: "\n\(appendedBody)")

        let saveButton = app.buttons["saveNoteButton"]
        saveButton.tap()

        let titleUpdatedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                noteTitleField.stringValue == updatedTitle
            },
            object: noteTitleField
        )
        let bodyUpdatedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                noteBodyEditor.stringValue.contains(appendedBody)
            },
            object: noteBodyEditor
        )

        XCTAssertEqual(
            XCTWaiter.wait(for: [titleUpdatedExpectation, bodyUpdatedExpectation], timeout: 5),
            .completed
        )

        XCTAssertEqual(noteTitleField.stringValue, updatedTitle)
        XCTAssertTrue(noteBodyEditor.stringValue.contains(appendedBody))

        navigateBackToNotesList(in: app)

        let searchField = app.searchFields["Search notes"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        replaceText(in: searchField, with: updatedTitle)
        XCTAssertTrue(app.staticTexts[updatedTitle].waitForExistence(timeout: 5))

        replaceText(in: searchField, with: "No matching note")
        XCTAssertFalse(app.staticTexts[updatedTitle].waitForExistence(timeout: 2))

        replaceText(in: searchField, with: updatedTitle)
        let updatedNoteRow = app.staticTexts[updatedTitle]
        XCTAssertTrue(updatedNoteRow.waitForExistence(timeout: 5))
        updatedNoteRow.tap()

        let deleteMenuButton = app.buttons["deleteNoteMenuButton"]
        XCTAssertTrue(deleteMenuButton.waitForExistence(timeout: 5))
        deleteMenuButton.tap()

        let deleteActionButton = app.buttons["deleteNoteActionButton"]
        XCTAssertTrue(deleteActionButton.waitForExistence(timeout: 5))
        deleteActionButton.tap()

        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[updatedTitle].exists)
    }

    @MainActor
    private func openQuickCapture(in app: XCUIApplication) {
        let quickCaptureButton = app.buttons["quickCaptureButton"]
        XCTAssertTrue(quickCaptureButton.waitForExistence(timeout: 5))
        quickCaptureButton.tap()
        XCTAssertTrue(app.navigationBars["Quick Capture"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func saveTextNote(in app: XCUIApplication, title: String, body: String) {
        let titleField = app.textFields["quickCaptureTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)

        let bodyEditor = app.textViews["quickCaptureBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText(body)

        let saveButton = app.buttons["saveTextNoteButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.navigationBars["Second Brain"].waitForExistence(timeout: 5) || app.staticTexts["Second Brain"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()

        if let currentValue = element.value as? String, !currentValue.isEmpty {
            let deleteText = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            element.typeText(deleteText)
        }

        element.typeText(text)
    }

    @MainActor
    private func appendTextToEditor(_ editor: XCUIElement, text: String) {
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.95)).tap()
        editor.typeText(text)
    }

    @MainActor
    private func navigateBackToNotesList(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons["Second Brain"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
        XCTAssertTrue(
            app.navigationBars["Second Brain"].waitForExistence(timeout: 5) ||
            app.staticTexts["Second Brain"].waitForExistence(timeout: 5)
        )
    }

    // MARK: - Accessibility identifier tests

    /// Verifies that the delete menu button and destructive action button carry the
    /// accessibility identifiers added in this PR so that UI tests (and assistive
    /// technology) can reliably locate them.
    @MainActor
    func testDeleteNoteAccessibilityIdentifiersExistInNoteDetail() throws {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()
        app.launch()

        openQuickCapture(in: app)
        saveTextNote(in: app, title: "Accessibility ID Test Note", body: "Testing delete button IDs.")

        let noteRow = app.staticTexts["Accessibility ID Test Note"]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        noteRow.tap()

        // The menu trigger button must be reachable by its identifier
        let deleteMenuButton = app.buttons["deleteNoteMenuButton"]
        XCTAssertTrue(deleteMenuButton.waitForExistence(timeout: 5),
                      "deleteNoteMenuButton must be present in NoteDetailView toolbar")

        // Tapping the menu reveals the destructive action button
        deleteMenuButton.tap()

        let deleteActionButton = app.buttons["deleteNoteActionButton"]
        XCTAssertTrue(deleteActionButton.waitForExistence(timeout: 5),
                      "deleteNoteActionButton must be present after opening delete menu")
    }

    // MARK: - Create then immediately delete (no edit step)

    /// Regression/boundary test: creating a note and immediately deleting it (without
    /// editing) should leave the list in the empty state.
    @MainActor
    func testCreateNoteAndDeleteWithoutEditing() throws {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()
        app.launch()

        let noteTitle = "Immediate Delete Note"

        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5))

        openQuickCapture(in: app)
        saveTextNote(in: app, title: noteTitle, body: "This note will be deleted right away.")

        let noteRow = app.staticTexts[noteTitle]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        noteRow.tap()

        let noteTitleField = app.textFields["noteTitleField"]
        XCTAssertTrue(noteTitleField.waitForExistence(timeout: 5))
        // No editing — go straight to delete
        let deleteMenuButton = app.buttons["deleteNoteMenuButton"]
        XCTAssertTrue(deleteMenuButton.waitForExistence(timeout: 5))
        deleteMenuButton.tap()

        let deleteActionButton = app.buttons["deleteNoteActionButton"]
        XCTAssertTrue(deleteActionButton.waitForExistence(timeout: 5))
        deleteActionButton.tap()

        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[noteTitle].exists)
    }

    // MARK: - Navigate back without saving

    /// Negative case: tapping the back button without pressing Save must not persist
    /// any changes to the note title.
    @MainActor
    func testNavigateBackWithoutSavingDoesNotPersistChanges() throws {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()
        app.launch()

        let originalTitle = "Back Without Save Note"
        let unsavedTitle = "Should Not Be Saved"

        openQuickCapture(in: app)
        saveTextNote(in: app, title: originalTitle, body: "Original body.")

        let noteRow = app.staticTexts[originalTitle]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        noteRow.tap()

        let noteTitleField = app.textFields["noteTitleField"]
        XCTAssertTrue(noteTitleField.waitForExistence(timeout: 5))

        // Change the title but do NOT save
        replaceText(in: noteTitleField, with: unsavedTitle)

        // Navigate back without saving
        navigateBackToNotesList(in: app)

        // Original title must still be present in the list
        XCTAssertTrue(app.staticTexts[originalTitle].waitForExistence(timeout: 5))
        // Unsaved title must NOT appear
        XCTAssertFalse(app.staticTexts[unsavedTitle].exists)
    }

    // MARK: - Deleted note absent from search

    /// Regression test: after deletion, searching for the deleted note's title must
    /// yield no results — verifying that search is not serving stale cached data.
    @MainActor
    func testDeletedNoteDoesNotAppearInSearchResults() throws {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()
        app.launch()

        let noteTitle = "Search After Delete Note"

        openQuickCapture(in: app)
        saveTextNote(in: app, title: noteTitle, body: "Will be deleted and then searched.")

        let noteRow = app.staticTexts[noteTitle]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        noteRow.tap()

        // Delete the note
        let deleteMenuButton = app.buttons["deleteNoteMenuButton"]
        XCTAssertTrue(deleteMenuButton.waitForExistence(timeout: 5))
        deleteMenuButton.tap()

        let deleteActionButton = app.buttons["deleteNoteActionButton"]
        XCTAssertTrue(deleteActionButton.waitForExistence(timeout: 5))
        deleteActionButton.tap()

        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5))

        // Now search for the deleted note's title
        let searchField = app.searchFields["Search notes"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceText(in: searchField, with: noteTitle)

        XCTAssertFalse(app.staticTexts[noteTitle].waitForExistence(timeout: 2),
                       "Deleted note must not appear in search results")
    }

    // MARK: - Edit body only (title unchanged)

    /// Boundary case: editing only the body (leaving the title untouched) and saving
    /// should preserve the original title in both the detail view and the notes list.
    @MainActor
    func testEditBodyOnlyPreservesTitle() throws {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()
        app.launch()

        let noteTitle = "Title Stays The Same"
        let originalBody = "Original body text."
        let appendedBody = "Appended body text."

        openQuickCapture(in: app)
        saveTextNote(in: app, title: noteTitle, body: originalBody)

        let noteRow = app.staticTexts[noteTitle]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        noteRow.tap()

        let noteTitleField = app.textFields["noteTitleField"]
        XCTAssertTrue(noteTitleField.waitForExistence(timeout: 5))
        XCTAssertEqual(noteTitleField.stringValue, noteTitle)

        let noteBodyEditor = app.textViews["noteBodyEditor"]
        appendTextToEditor(noteBodyEditor, text: " \(appendedBody)")
        app.buttons["saveNoteButton"].tap()

        let bodyUpdatedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                noteBodyEditor.stringValue.contains(appendedBody)
            },
            object: noteBodyEditor
        )

        XCTAssertEqual(
            XCTWaiter.wait(for: [bodyUpdatedExpectation], timeout: 5),
            .completed
        )

        XCTAssertEqual(noteTitleField.stringValue, noteTitle)
        XCTAssertTrue(noteBodyEditor.stringValue.contains(appendedBody))

        navigateBackToNotesList(in: app)
        XCTAssertTrue(app.staticTexts[noteTitle].waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    var stringValue: String {
        value as? String ?? ""
    }
}
