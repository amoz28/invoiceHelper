# Voice invoice input

Dictate invoice line items in English or Romanian instead of typing them.

## Where it appears

- **Dashboard**: a blue floating microphone button, bottom right. Pick a customer, dictate, and the invoice is created and opened for you.
- **Invoice editor**: an "Add via voice" row in the Line items section, next to "Add Item" and "Add from saved items".

## Files

| File | Role |
|---|---|
| `VoiceRecognitionManager.swift` | Wraps `SFSpeechRecognizer`. Requests permissions, runs the audio engine, publishes the transcript. |
| `TranslationService.swift` | Romanian to English. Tries MyMemory over the network, falls back to a built in glossary. |
| `VoiceCommandParser.swift` | Turns a sentence into line items, a tax rate, or a note. Rule based, no network. |
| `VoiceInputView.swift` | The dictation sheet: language toggle, live transcript, preview, confirm. |
| `VoiceQuickEntrySheet.swift` | Dashboard flow: choose customer, dictate, save. |
| `InvoiceEditorVoiceExtension.swift` | Writes the parsed result into the editor's form state. |

## What you can say

**Line items** are matched as `<quantity> <description> at <price>`:

- "Two hours web design at fifty"
- "3 days consulting at 120"
- "5 x cleaning for 40"

Spoken number words are converted to digits before parsing, so "fifty" and "50" both work.

**Tax**: "Set tax to twenty percent". The value snaps to the nearest rate in `InvoiceLogic.taxRates`.

**Notes**: "Note, payment due within thirty days".

Romanian equivalents run through translation first, for example "doua ore dezvoltare la 50" becomes "2 hours development at 50".

## Offline behaviour

Speech recognition requests on-device recognition where the device supports it, so dictation works with no network. Translation tries the network with a 4 second timeout and falls back to the glossary, which covers numbers, common invoice vocabulary, and typical trade descriptions. The glossary is word for word, so long free-form Romanian sentences will translate poorly offline; short command phrases are the intended case.

## Permissions

Both usage strings are set as `INFOPLIST_KEY_*` build settings in the project, since this target uses `GENERATE_INFOPLIST_FILE = YES` rather than a checked-in Info.plist:

- `INFOPLIST_KEY_NSMicrophoneUsageDescription`
- `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`

## Known limits

- Parsing is regex based. Phrasings outside the patterns above fall through to a description-only item with no price, and the sheet tells the user what to say instead.
- The Romanian glossary is small. Extend `TranslationService.glossary` as you hit gaps.
- Only the first matching pattern is used per utterance, so one sentence produces one item. Dictate items one at a time.
- Not yet verified on a physical device. Simulator microphone input is unreliable for speech recognition; test on hardware.
