# Readable controls at large text sizes

The current iPhone 17 simulator reproduces two layout issues: accessibility text sizes split the source-language title across narrow columns, and the broadcast guide compresses its explanatory text because all content must fit without scrolling.

Keep the existing neutral layout at regular sizes. At accessibility sizes, stack the two language choices vertically and update their layout when text size changes. Make the broadcast explanation scrollable while keeping Cancel outside the scroll area, above the bottom safe area. Give the system broadcast button a useful VoiceOver label instead of its default ModuleIcon name.

Verify the actual native screen at regular and maximum text sizes, including scrolling the full guide, cancelling, restarting, and changing size while it is open. Keep the existing capture lifecycle and credential storage. Build and install the same source on iPhone; a simulator layout check does not complete the remaining physical cross-app long test.
