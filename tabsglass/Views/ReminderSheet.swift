//
//  ReminderSheet.swift
//  tabsglass
//
//  Sheet for setting reminders with date, time, and repeat options
//

import SwiftUI

struct ReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var themeManager: ThemeManager { ThemeManager.shared }

    @State private var selectedDate: Date
    @State private var selectedTime: Date
    @State private var repeatInterval: ReminderRepeatInterval
    @State private var isReminderActive: Bool

    private let originalDate: Date?
    private let originalRepeatInterval: ReminderRepeatInterval?

    let message: Message
    let onSave: (Date, ReminderRepeatInterval) -> Void
    let onRemove: (() -> Void)?

    init(
        message: Message,
        onSave: @escaping (Date, ReminderRepeatInterval) -> Void,
        onRemove: (() -> Void)?
    ) {
        self.message = message
        self.onSave = onSave
        self.onRemove = onRemove

        // Initialize with existing reminder or default to now + 1 hour
        let defaultDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let initialDate = message.reminderDate ?? defaultDate

        _selectedDate = State(initialValue: initialDate)
        _selectedTime = State(initialValue: initialDate)
        _repeatInterval = State(initialValue: message.reminderRepeatInterval ?? .never)
        _isReminderActive = State(initialValue: message.reminderDate != nil)

        // Store original values to detect changes
        self.originalDate = message.reminderDate
        self.originalRepeatInterval = message.reminderRepeatInterval
    }

    /// Check if user has modified the date/time/repeat from the original reminder
    private var hasChangedFromOriginal: Bool {
        guard let original = originalDate else { return false }

        let calendar = Calendar.current
        let originalComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: original)
        let currentComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: combinedDateTime)

        let dateChanged = originalComponents != currentComponents
        let repeatChanged = repeatInterval != (originalRepeatInterval ?? .never)

        return dateChanged || repeatChanged
    }

    private var combinedDateTime: Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)

        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute

        return calendar.date(from: combined) ?? selectedDate
    }

    private var buttonText: String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: selectedTime)

        if calendar.isDateInToday(selectedDate) {
            return String(format: L10n.Reminder.sendToday, timeString)
        } else if calendar.isDateInTomorrow(selectedDate) {
            return String(format: L10n.Reminder.sendTomorrow, timeString)
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "d MMM"
            let dateString = dateFormatter.string(from: selectedDate)
            return String(format: L10n.Reminder.sendOnDate, dateString, timeString)
        }
    }

    private var accentColor: Color {
        themeManager.currentTheme.accentColor ?? .blue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Calendar
                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Divider()
                    .padding(.vertical, 8)

                // Time and Repeat rows
                VStack(spacing: 0) {
                    // Time row
                    HStack {
                        Text(L10n.Reminder.time)
                            .foregroundStyle(.primary)

                        Spacer()

                        DatePicker(
                            "",
                            selection: $selectedTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    Divider()
                        .padding(.leading)

                    // Repeat row
                    HStack {
                        Text(L10n.Reminder.repeatLabel)
                            .foregroundStyle(.primary)

                        Spacer()

                        Menu {
                            ForEach(ReminderRepeatInterval.allCases, id: \.self) { interval in
                                Button {
                                    repeatInterval = interval
                                } label: {
                                    HStack {
                                        Text(localizedInterval(interval))
                                        if repeatInterval == interval {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(localizedInterval(repeatInterval))
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }

                Spacer()

                // Bottom button
                VStack(spacing: 12) {
                    if isReminderActive && !hasChangedFromOriginal {
                        // Red button to remove reminder (only if nothing changed)
                        Button {
                            onRemove?()
                            isReminderActive = false
                        } label: {
                            Text(L10n.Reminder.remove)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .padding(.horizontal)
                    } else {
                        // Blue button to set/update reminder
                        Button {
                            onSave(combinedDateTime, repeatInterval)
                            dismiss()
                        } label: {
                            Text(buttonText)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle(L10n.Reminder.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .tint(accentColor)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func localizedInterval(_ interval: ReminderRepeatInterval) -> String {
        switch interval {
        case .never: return L10n.Reminder.repeatNever
        case .daily: return L10n.Reminder.repeatDaily
        case .weekly: return L10n.Reminder.repeatWeekly
        case .biweekly: return L10n.Reminder.repeatBiweekly
        case .monthly: return L10n.Reminder.repeatMonthly
        case .quarterly: return L10n.Reminder.repeatQuarterly
        case .semiannually: return L10n.Reminder.repeatSemiannually
        case .yearly: return L10n.Reminder.repeatYearly
        }
    }
}
