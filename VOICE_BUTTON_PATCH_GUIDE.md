# Voice Integration - Exact Code Patches

Follow this EXACTLY to get the "Add via voice" button and FAB working.

---

## PATCH 1: InvoiceEditorView.swift - Add Voice State Variable

**Location:** Near the top of the struct, where other @State variables are

**FIND THIS:**
```swift
@State private var showSavedItemsPicker = false
```

**ADD AFTER IT:**
```swift
@State private var showVoiceInput = false
```

**RESULT:**
```swift
@State private var showSavedItemsPicker = false
@State private var showVoiceInput = false
```

---

## PATCH 2: InvoiceEditorView.swift - Add Voice Button in Line Items Section

**Location:** In the `Section("Line items")` block

**FIND THIS CODE:**
```swift
Button {
    showSavedItemsPicker = true
} label: {
    Label("Add from saved items", systemImage: "tray.and.arrow.down")
}
```

**REPLACE WITH:**
```swift
Button {
    showVoiceInput = true
} label: {
    Label("Add via voice", systemImage: "mic.circle.fill")
}
.tint(AppTheme.infoBlue)

Button {
    showSavedItemsPicker = true
} label: {
    Label("Add from saved items", systemImage: "tray.and.arrow.down")
}
```

**RESULT:** You now have two buttons: "Add via voice" and "Add from saved items"

---

## PATCH 3: InvoiceEditorView.swift - Add Voice Input Sheet

**Location:** At the END of the Form (before `.navigationTitle`)

**FIND THIS:**
```swift
Section {
    Button(mode == .create ? "Create invoice" : "Save changes") { Task { await save() } }
        .buttonStyle(PrimaryFormButtonStyle())
        .disabled(customerId.isEmpty || !linesValid)
}
```

**ADD AFTER THE FORM CLOSING BRACE (after the `}`), but BEFORE `.navigationTitle`:**
```swift
.sheet(isPresented: $showVoiceInput) {
    VoiceInputView(
        isPresented: $showVoiceInput,
        onItemsAdded: { voiceItems in
            VoiceInvoiceIntegration.addVoiceItems(voiceItems, to: &lines)
        },
        onNoteAdded: { note in
            VoiceInvoiceIntegration.addVoiceNote(note, to: &notes)
        },
        onTaxRateChanged: { rate in
            VoiceInvoiceIntegration.applyVoiceTaxRate(rate, to: &taxRate)
        }
    )
}
```

**FINAL STRUCTURE:**
```swift
Form {
    // ... existing code ...
    
    Section {
        Button(mode == .create ? "Create invoice" : "Save changes") { Task { await save() } }
            .buttonStyle(PrimaryFormButtonStyle())
            .disabled(customerId.isEmpty || !linesValid)
    }
}
.sheet(isPresented: $showVoiceInput) {
    VoiceInputView(
        isPresented: $showVoiceInput,
        onItemsAdded: { voiceItems in
            VoiceInvoiceIntegration.addVoiceItems(voiceItems, to: &lines)
        },
        onNoteAdded: { note in
            VoiceInvoiceIntegration.addVoiceNote(note, to: &notes)
        },
        onTaxRateChanged: { rate in
            VoiceInvoiceIntegration.applyVoiceTaxRate(rate, to: &taxRate)
        }
    )
}
.navigationTitle("")
.navigationBarTitleDisplayMode(.inline)
```

---

## PATCH 4: InvoiceListView.swift - Add Voice FAB Button

**Location:** In the toolbar section of InvoiceListView

**FIND THIS:**
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        NavigationLink("New") {
            InvoiceEditorView(mode: .create, invoiceId: nil, onInvoiceCreated: { id in
                previewInvoiceId = id
                showInvoicePreview = true
            })
        }
    }
}
```

**ADD A STATE VARIABLE AT THE TOP:**
```swift
@State private var showVoiceQuickEntry = false
```

**REPLACE THE TOOLBAR WITH:**
```swift
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        // Voice FAB
        Button {
            showVoiceQuickEntry = true
        } label: {
            Image(systemName: "mic.circle.fill")
                .font(.title2)
        }
        .tint(AppTheme.infoBlue)
        
        // New Invoice button
        NavigationLink("New") {
            InvoiceEditorView(mode: .create, invoiceId: nil, onInvoiceCreated: { id in
                previewInvoiceId = id
                showInvoicePreview = true
            })
        }
    }
}
```

**ADD THIS SHEET AFTER THE TOOLBAR (before .onAppear):**
```swift
.sheet(isPresented: $showVoiceQuickEntry) {
    VoiceQuickEntrySheet(isPresented: $showVoiceQuickEntry)
        .environmentObject(store)
}
```

---

## PATCH 5: Create VoiceQuickEntrySheet.swift - FAB Handler

**Create a new file:** `InvoiceHelper/VoiceQuickEntrySheet.swift`

**Content:**
```swift
import SwiftUI

struct VoiceQuickEntrySheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    
    @State private var selectedCustomerId: String?
    @State private var showVoiceInput = false
    @State private var tempLines: [InvoiceEditorView.LineRow] = []
    @State private var tempTaxRate: Double = 20
    @State private var tempNotes = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if selectedCustomerId == nil {
                    // Step 1: Select Customer
                    List {
                        ForEach(store.customers) { customer in
                            Button {
                                selectedCustomerId = customer.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(customer.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(customer.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Customer")
                } else {
                    // Step 2: Voice Input
                    VoiceInputView(
                        isPresented: $showVoiceInput,
                        onItemsAdded: { voiceItems in
                            VoiceInvoiceIntegration.addVoiceItems(voiceItems, to: &tempLines)
                            createInvoice()
                        },
                        onNoteAdded: { note in
                            VoiceInvoiceIntegration.addVoiceNote(note, to: &tempNotes)
                        },
                        onTaxRateChanged: { rate in
                            VoiceInvoiceIntegration.applyVoiceTaxRate(rate, to: &tempTaxRate)
                        }
                    )
                    .onAppear {
                        showVoiceInput = true
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func createInvoice() {
        guard let customerId = selectedCustomerId, !tempLines.isEmpty else { return }
        
        let items = tempLines.compactMap { row -> InvoiceItem? in
            let desc = row.description.trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty,
                  let q = Double(row.quantity.replacingOccurrences(of: ",", with: ".")),
                  let p = Double(row.unitPrice.replacingOccurrences(of: ",", with: ".")),
                  q > 0 else { return nil }
            return InvoiceItem(description: desc, quantity: q, unitPrice: p)
        }
        
        guard !items.isEmpty else { return }
        
        Task {
            do {
                _ = try await store.addInvoice(
                    customerId: customerId,
                    items: items,
                    taxRate: tempTaxRate,
                    date: ISO8601DateFormatter().string(from: Date()),
                    dueDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * store.defaultInvoiceDueDaysFromInvoiceDate)),
                    notes: tempNotes.isEmpty ? nil : tempNotes,
                    terms: nil
                )
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                print("Error creating invoice: \(error)")
            }
        }
    }
}
```

---

## VERIFICATION CHECKLIST

After applying all patches:

- [ ] Patch 1: `@State private var showVoiceInput = false` added to InvoiceEditorView
- [ ] Patch 2: "Add via voice" button appears in Line items section
- [ ] Patch 3: Voice sheet added to InvoiceEditorView
- [ ] Patch 4: Voice FAB (mic icon) appears next to "New" button in InvoiceListView
- [ ] Patch 5: VoiceQuickEntrySheet.swift file created
- [ ] Project compiles without errors (Cmd+B)
- [ ] App runs without crashes (Cmd+R)
- [ ] "Add via voice" button visible in invoice editor
- [ ] Mic FAB visible in invoices list
- [ ] Both buttons open voice input

---

## IMPORTANT: File Structure for Xcode

Make sure files are in correct locations:

```
InvoiceHelper/
├── InvoiceViews.swift (MODIFIED - add voice button)
├── VoiceRecognitionManager.swift ✓
├── TranslationService.swift ✓
├── VoiceCommandParser.swift ✓
├── VoiceInputView.swift ✓ (UPDATED)
├── VoiceQuickEntrySheet.swift (NEW)
├── InvoiceEditorVoiceExtension.swift ✓
└── ... other files
```

---

## TROUBLESHOOTING

**"Add via voice" button not showing:**
- Check Patch 2 was applied correctly
- Rebuild project (Cmd+B)
- Clean build folder (Shift+Cmd+K) then rebuild

**Mic FAB not showing:**
- Check Patch 4 was applied correctly
- Make sure ToolbarItemGroup is used (not ToolbarItem)
- Check VoiceQuickEntrySheet is created

**Crashes when clicking button:**
- Ensure VoiceQuickEntrySheet.swift is created
- Check InvoiceEditorVoiceExtension.swift exists
- Verify all 5 files are in project

---

## NEXT STEP

Once you've applied all patches:

1. Run: `git add -A`
2. Run: `git commit -m "fix: Properly integrate voice button and FAB"`
3. Run: `git push origin feature/voice-integration`
4. Create PR on GitHub

Done! 🎉
