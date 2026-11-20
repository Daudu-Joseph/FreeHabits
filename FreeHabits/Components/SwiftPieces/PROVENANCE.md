# SwiftPieces component use

- Component: `TaskRow`
- Source version: SwiftPieces v2.2.0 registry component
- Source page: https://swiftpieces.com/docs/components/lists/task-row
- Used by: `FreeHabitsWidget/FreeHabitsWidget.swift` for the habit row visual in the Home Screen widget.
- WidgetKit and App Intents provide the extension container, timeline, and Done/Snooze/Skip actions. SwiftPieces does not provide a WidgetKit extension component.
- `TaskRow.swift` is copied from the published component source with its copyright and license notice. The component is used as a presentational row in the widget; its in-app swipe/drag gestures are not enabled there.
