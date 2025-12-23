//
//  Views/Calendar/CalendarDayDetailComponents.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/10/19.
//

import SwiftUI

struct DayTodoRow: View {
    let date: Date
    let todo: CalendarTodo
    let accent: Color
    let onToggle: (UUID) -> Void
    let onEditDue: (UUID, Date?) -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var showDuePicker = false
    @State private var tempDue: Date = Date()

    @State private var isRenaming = false
    @State private var tempTitle = ""
    @FocusState private var titleFocused: Bool

    private var cal: Calendar { .current }

    var body: some View {
        HStack(spacing: 10) {
            Button { onToggle(todo.id) } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                if isRenaming {
                    HStack(spacing: 8) {
                        TextField("タイトル", text: $tempTitle)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                            .submitLabel(.done)
                            .onSubmit { commitRename() }

                        Button {
                            commitRename()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .onAppear {
                        tempTitle = todo.title
                        titleFocused = true
                    }
                } else {
                    Text(todo.title)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(todo.done, pattern: .solid, color: .secondary)
                        .foregroundStyle(todo.done ? .secondary : .primary)
                        .onTapGesture { isRenaming = true }
                }

                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if let due = todo.due {
                            if cal.isDateInToday(due) {
                                Circle().fill(Color.blue).frame(width: 6, height: 6)
                            }
                            Text(dueLabel(due))
                                .font(.caption)
                                .foregroundStyle(isOverdue(due) && !todo.done ? .red : .secondary)
                        } else {
                            Text("期日なし")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                    .onTapGesture {
                        tempDue = todo.due ?? date
                        showDuePicker = true
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(todo.id)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .popover(isPresented: $showDuePicker, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            DuePopover(
                month: date,
                accent: accent,
                tempDate: $tempDue,
                onSave: { newDate in
                    onEditDue(todo.id, newDate)
                    showDuePicker = false
                },
                onClear: {
                    onEditDue(todo.id, nil)
                    showDuePicker = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    private func commitRename() {
        let t = tempTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != todo.title {
            onRename(todo.id, t)
        }
        isRenaming = false
        titleFocused = false
    }

    private func dueLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .init(identifier: "ja_JP")
        f.dateFormat = "M/d(EEE)"
        return f.string(from: d)
    }

    private func isOverdue(_ d: Date) -> Bool {
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: d)
        return due < today
    }
}

struct AddTodoMiniSheet: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    let accent: Color
    @Binding var title: String
    let onAdd: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("ToDoを追加")
                .font(.headline)

            TextField("タイトル（例：電気代の支払い）", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.done)
                .onAppear { focused = true }

            HStack {
                Button("キャンセル", role: .cancel) { onCancel() }
                    .tint(.red)
                Spacer()
                Button {
                    onAdd()
                } label: {
                    Text("追加")
                        .frame(minWidth: 60, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .padding(16)
        .background(themeStore.theme.backgroundColor(for: scheme))
    }
}

struct DayNoteEditor: View {
    @EnvironmentObject var dayNotes: DayNotesStore
    let date: Date
    let accent: Color

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(minHeight: 48)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.quaternary)
                    )
                if text.isEmpty {
                    Text("例：北海道旅行など")
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Button("削除", role: .destructive) {
                    text = ""
                    dayNotes.removeNote(for: date)
                }

                Spacer()

                Button("保存") {
                    dayNotes.setNote(text, for: date)
                    hideKeyboard()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .onAppear { text = dayNotes.note(for: date) }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
