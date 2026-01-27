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
    }

    // MARK: - Themes
    enum Theme {
        static var system: String { NSLocalizedString("theme.system", comment: "System theme") }
        static var light: String { NSLocalizedString("theme.light", comment: "Light theme") }
        static var dark: String { NSLocalizedString("theme.dark", comment: "Dark theme") }
        static var pink: String { NSLocalizedString("theme.pink", comment: "Pink theme") }
        static var beige: String { NSLocalizedString("theme.beige", comment: "Beige theme") }
        static var green: String { NSLocalizedString("theme.green", comment: "Green theme") }
        static var brown: String { NSLocalizedString("theme.brown", comment: "Brown theme") }
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

    // MARK: - Composer
    enum Composer {
        static var placeholder: String { NSLocalizedString("composer.placeholder", comment: "Composer placeholder") }
        static var camera: String { NSLocalizedString("composer.camera", comment: "Camera option") }
        static var photo: String { NSLocalizedString("composer.photo", comment: "Photo option") }
    }
}
