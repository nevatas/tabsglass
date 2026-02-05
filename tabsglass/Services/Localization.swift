//
//  Localization.swift
//  tabsglass
//
//  String localization helpers
//

import Foundation

// MARK: - Localization Keys

enum L10n {
    // MARK: - Settings
    enum Settings {
        static var title: String { NSLocalizedString("settings.title", comment: "Settings screen title") }
        static var appearance: String { NSLocalizedString("settings.appearance", comment: "Appearance settings") }
        static var reorderTabs: String { NSLocalizedString("settings.reorder_tabs", comment: "Reorder tabs option") }
        static var autoFocus: String { NSLocalizedString("settings.auto_focus", comment: "Auto-focus input toggle") }
        static var privacyPolicy: String { NSLocalizedString("settings.privacy_policy", comment: "Privacy policy link") }
        static var terms: String { NSLocalizedString("settings.terms", comment: "Terms of service link") }
        static var contact: String { NSLocalizedString("settings.contact", comment: "Contact developer link") }
        static var done: String { NSLocalizedString("settings.done", comment: "Done button") }
        static var spaceName: String { NSLocalizedString("settings.space_name", comment: "Space name setting") }
        static var autoFocusFooter: String { NSLocalizedString("settings.auto_focus_footer", comment: "Auto-focus explanation") }
    }

    // MARK: - Reorder
    enum Reorder {
        static var title: String { NSLocalizedString("reorder.title", comment: "Reorder screen title") }
        static var inbox: String { NSLocalizedString("reorder.inbox", comment: "Inbox label") }
        static var inboxFooter: String { NSLocalizedString("reorder.inbox_footer", comment: "Inbox footer text") }
    }

    // MARK: - Tabs
    enum Tab {
        static var new: String { NSLocalizedString("tab.new", comment: "New tab alert title") }
        static var newHint: String { NSLocalizedString("tab.new_hint", comment: "New tab alert message") }
        static var rename: String { NSLocalizedString("tab.rename", comment: "Rename action") }
        static var renameInbox: String { NSLocalizedString("tab.rename_inbox", comment: "Rename inbox alert title") }
        static var deleteTitle: String { NSLocalizedString("tab.delete_title", comment: "Delete tab alert title") }
        static func deleteMessage(_ title: String) -> String {
            String(format: NSLocalizedString("tab.delete_message", comment: "Delete tab message"), title)
        }
        static var titlePlaceholder: String { NSLocalizedString("tab.title_placeholder", comment: "Tab title placeholder") }
        static var create: String { NSLocalizedString("tab.create", comment: "Create button") }
        static var save: String { NSLocalizedString("tab.save", comment: "Save button") }
        static var move: String { NSLocalizedString("tab.move", comment: "Move tab action") }
        static var delete: String { NSLocalizedString("tab.delete", comment: "Delete button") }
        static var cancel: String { NSLocalizedString("tab.cancel", comment: "Cancel button") }
    }

    // MARK: - Context Menu
    enum Menu {
        static var copy: String { NSLocalizedString("menu.copy", comment: "Copy action") }
        static var edit: String { NSLocalizedString("menu.edit", comment: "Edit action") }
        static var move: String { NSLocalizedString("menu.move", comment: "Move action") }
        static var delete: String { NSLocalizedString("menu.delete", comment: "Delete action") }
        static var restoreTitle: String { NSLocalizedString("menu.restore_title", comment: "Restore note alert title") }
        static var restoreMessage: String { NSLocalizedString("menu.restore_message", comment: "Restore note message") }
        static var restore: String { NSLocalizedString("menu.restore", comment: "Restore action") }
        static var remind: String { NSLocalizedString("menu.remind", comment: "Remind action") }
        static var editReminder: String { NSLocalizedString("menu.edit_reminder", comment: "Edit reminder action") }
        static var removeReminder: String { NSLocalizedString("menu.remove_reminder", comment: "Remove reminder action") }
    }

    // MARK: - Themes
    enum Theme {
        static var system: String { NSLocalizedString("theme.system", comment: "System theme") }
        static var light: String { NSLocalizedString("theme.light", comment: "Light theme") }
        static var dark: String { NSLocalizedString("theme.dark", comment: "Dark theme") }
        static var pink: String { NSLocalizedString("theme.pink", comment: "Pink theme") }
        static var beige: String { NSLocalizedString("theme.beige", comment: "Beige theme") }
        static var green: String { NSLocalizedString("theme.green", comment: "Green theme") }
        static var blue: String { NSLocalizedString("theme.blue", comment: "Blue theme") }
    }

    // MARK: - Empty State
    enum Empty {
        static var title: String { NSLocalizedString("empty.title", comment: "Empty state title") }
        static var subtitle: String { NSLocalizedString("empty.subtitle", comment: "Empty state subtitle") }
    }

    // MARK: - Formatting
    enum Format {
        static var menu: String { NSLocalizedString("format.menu", comment: "Format menu title") }
        static var bold: String { NSLocalizedString("format.bold", comment: "Bold formatting") }
        static var italic: String { NSLocalizedString("format.italic", comment: "Italic formatting") }
        static var underline: String { NSLocalizedString("format.underline", comment: "Underline formatting") }
        static var strikethrough: String { NSLocalizedString("format.strikethrough", comment: "Strikethrough formatting") }
        static var link: String { NSLocalizedString("format.link", comment: "Link formatting") }
        static var addLink: String { NSLocalizedString("format.add_link", comment: "Add link title") }
    }

    // MARK: - Welcome
    enum Welcome {
        static var message1: String { NSLocalizedString("welcome.message1", comment: "Welcome message 1") }
        static var message2: String { NSLocalizedString("welcome.message2", comment: "Welcome message 2") }
        static var message3: String { NSLocalizedString("welcome.message3", comment: "Welcome message 3") }
        static var message4: String { NSLocalizedString("welcome.message4", comment: "Welcome message 4") }
    }

    // MARK: - Composer
    enum Composer {
        static var placeholder: String { NSLocalizedString("composer.placeholder", comment: "Composer placeholder") }
        static var camera: String { NSLocalizedString("composer.camera", comment: "Camera option") }
        static var gallery: String { NSLocalizedString("composer.gallery", comment: "Gallery option") }
        static var list: String { NSLocalizedString("composer.list", comment: "List option") }
    }

    // MARK: - Task List
    enum TaskList {
        static var title: String { NSLocalizedString("tasklist.title", comment: "Task list sheet title") }
        static var titlePlaceholder: String { NSLocalizedString("tasklist.title_placeholder", comment: "Task list title placeholder") }
        static var itemPlaceholder: String { NSLocalizedString("tasklist.item_placeholder", comment: "Task item placeholder") }
        static var addItem: String { NSLocalizedString("tasklist.add_item", comment: "Add task button") }
        static func completed(_ completed: Int, _ total: Int) -> String {
            String(format: NSLocalizedString("tasklist.completed", comment: "Completed count"), completed, total)
        }
    }

    // MARK: - Reminder
    enum Reminder {
        static var title: String { NSLocalizedString("reminder.title", comment: "Reminder sheet title") }
        static var time: String { NSLocalizedString("reminder.time", comment: "Time label") }
        static var repeatLabel: String { NSLocalizedString("reminder.repeat", comment: "Repeat label") }
        static var remove: String { NSLocalizedString("reminder.remove", comment: "Remove reminder button") }

        // Repeat intervals
        static var repeatNever: String { NSLocalizedString("reminder.repeat_never", comment: "Never repeat") }
        static var repeatDaily: String { NSLocalizedString("reminder.repeat_daily", comment: "Daily repeat") }
        static var repeatWeekly: String { NSLocalizedString("reminder.repeat_weekly", comment: "Weekly repeat") }
        static var repeatBiweekly: String { NSLocalizedString("reminder.repeat_biweekly", comment: "Biweekly repeat") }
        static var repeatMonthly: String { NSLocalizedString("reminder.repeat_monthly", comment: "Monthly repeat") }
        static var repeatQuarterly: String { NSLocalizedString("reminder.repeat_quarterly", comment: "Quarterly repeat") }
        static var repeatSemiannually: String { NSLocalizedString("reminder.repeat_semiannually", comment: "Semiannually repeat") }
        static var repeatYearly: String { NSLocalizedString("reminder.repeat_yearly", comment: "Yearly repeat") }

        // Button text
        static var sendToday: String { NSLocalizedString("reminder.send_today", comment: "Send today button prefix") }
        static var sendTomorrow: String { NSLocalizedString("reminder.send_tomorrow", comment: "Send tomorrow button prefix") }
        static var sendOnDate: String { NSLocalizedString("reminder.send_on_date", comment: "Send on date button prefix") }

        // Notifications
        static var notificationTitle: String { NSLocalizedString("reminder.notification_title", comment: "Notification title") }
        static var notificationBodyEmpty: String { NSLocalizedString("reminder.notification_body_empty", comment: "Notification body for empty message") }
    }

    // MARK: - Share Extension
    enum Share {
        static var title: String { NSLocalizedString("share.title", comment: "Share extension title") }
        static var cancel: String { NSLocalizedString("share.cancel", comment: "Cancel button") }
        static var save: String { NSLocalizedString("share.save", comment: "Save button") }
        static var saveTo: String { NSLocalizedString("share.save_to", comment: "Save to section header") }
        static var inbox: String { NSLocalizedString("share.inbox", comment: "Inbox option") }
        static var inboxInfo: String { NSLocalizedString("share.inbox_info", comment: "Info about saving to inbox") }
        static var whereToSave: String { NSLocalizedString("share.where_to_save", comment: "Where to save title") }
    }

    // MARK: - Tips
    enum Tips {
        static var title: String { NSLocalizedString("tips.title", comment: "Tips section title") }
        static var edgeSwipe: String { NSLocalizedString("tips.edge_swipe", comment: "Tip: swipe from left edge") }
        static var shakeUndo: String { NSLocalizedString("tips.shake_undo", comment: "Tip: shake to undo delete") }
        static var formatting: String { NSLocalizedString("tips.formatting", comment: "Tip: text formatting") }
    }

    // MARK: - Search
    enum Search {
        static var title: String { NSLocalizedString("search.title", comment: "Search screen title") }
        static var placeholder: String { NSLocalizedString("search.placeholder", comment: "Search placeholder") }
    }

    // MARK: - Selection
    enum Selection {
        static var select: String { NSLocalizedString("selection.select", comment: "Select action") }
        static var move: String { NSLocalizedString("selection.move", comment: "Move action") }
        static var delete: String { NSLocalizedString("selection.delete", comment: "Delete action") }
        static var moveTo: String { NSLocalizedString("selection.move_to", comment: "Move to title") }
        static func count(_ n: Int) -> String {
            String(format: NSLocalizedString("selection.count", comment: "Selected count"), n)
        }
    }

    // MARK: - Data (Export/Import)
    enum Data {
        static var title: String { NSLocalizedString("data.title", comment: "Data section title") }
        static var export: String { NSLocalizedString("data.export", comment: "Export button") }
        static var importData: String { NSLocalizedString("data.import", comment: "Import button") }
        static var exporting: String { NSLocalizedString("data.exporting", comment: "Exporting progress title") }
        static var importing: String { NSLocalizedString("data.importing", comment: "Importing progress title") }
        static var exportSuccess: String { NSLocalizedString("data.export_success", comment: "Export success message") }
        static var importSuccess: String { NSLocalizedString("data.import_success", comment: "Import success message") }
        static var exportError: String { NSLocalizedString("data.export_error", comment: "Export error message") }
        static var importError: String { NSLocalizedString("data.import_error", comment: "Import error message") }

        // Preview
        static var importPreviewTitle: String { NSLocalizedString("data.import_preview_title", comment: "Import preview title") }
        static var previewArchiveInfo: String { NSLocalizedString("data.preview_archive_info", comment: "Archive info section") }
        static var previewContents: String { NSLocalizedString("data.preview_contents", comment: "Contents section") }
        static var previewDate: String { NSLocalizedString("data.preview_date", comment: "Export date label") }
        static var previewDevice: String { NSLocalizedString("data.preview_device", comment: "Device name label") }
        static var previewAppVersion: String { NSLocalizedString("data.preview_app_version", comment: "App version label") }
        static var previewTabs: String { NSLocalizedString("data.preview_tabs", comment: "Tabs count label") }
        static var previewMessages: String { NSLocalizedString("data.preview_messages", comment: "Messages count label") }
        static var previewPhotos: String { NSLocalizedString("data.preview_photos", comment: "Photos count label") }
        static var previewVideos: String { NSLocalizedString("data.preview_videos", comment: "Videos count label") }

        // Import modes
        static var importMode: String { NSLocalizedString("data.import_mode", comment: "Import mode section") }
        static var modeReplace: String { NSLocalizedString("data.mode_replace", comment: "Replace mode") }
        static var modeReplaceDescription: String { NSLocalizedString("data.mode_replace_description", comment: "Replace mode description") }
        static var modeReplaceWarning: String { NSLocalizedString("data.mode_replace_warning", comment: "Replace mode warning") }
        static var modeMerge: String { NSLocalizedString("data.mode_merge", comment: "Merge mode") }
        static var modeMergeDescription: String { NSLocalizedString("data.mode_merge_description", comment: "Merge mode description") }
        static var importButton: String { NSLocalizedString("data.import_button", comment: "Import button") }

        // Import stats
        static func importedStats(_ tabs: Int, _ messages: Int) -> String {
            String(format: NSLocalizedString("data.imported_stats", comment: "Imported stats"), tabs, messages)
        }

        // Progress phases
        static var phasePrepairing: String { NSLocalizedString("data.phase_preparing", comment: "Preparing phase") }
        static var phaseExportingData: String { NSLocalizedString("data.phase_exporting_data", comment: "Exporting data phase") }
        static var phaseCopyingPhotos: String { NSLocalizedString("data.phase_copying_photos", comment: "Copying photos phase") }
        static var phaseCopyingVideos: String { NSLocalizedString("data.phase_copying_videos", comment: "Copying videos phase") }
        static var phaseCompressing: String { NSLocalizedString("data.phase_compressing", comment: "Compressing phase") }
        static var phaseExtracting: String { NSLocalizedString("data.phase_extracting", comment: "Extracting phase") }
        static var phaseImportingData: String { NSLocalizedString("data.phase_importing_data", comment: "Importing data phase") }
        static var phaseCopyingMedia: String { NSLocalizedString("data.phase_copying_media", comment: "Copying media phase") }
        static var phaseSchedulingReminders: String { NSLocalizedString("data.phase_scheduling_reminders", comment: "Scheduling reminders phase") }
        static var phaseComplete: String { NSLocalizedString("data.phase_complete", comment: "Complete phase") }
    }
}
