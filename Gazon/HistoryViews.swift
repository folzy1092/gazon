import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \IntakeSession.createdAt, order: .reverse) private var sessions: [IntakeSession]
    var body: some View {
        List(sessions.filter(\.isCompleted)) { session in
            NavigationLink {
                IntakeDetailView(session: session)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startTime.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                    Text("\(session.totalItems) отправлений")
                    Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) → \((session.completedAt ?? session.lastTime).formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if sessions.filter(\.isCompleted).isEmpty {
                ContentUnavailableView("История пуста", systemImage: "clock")
            }
        }
        .navigationTitle("История")
    }
}

struct IntakeDetailView: View {
    @Bindable var session: IntakeSession
    @Environment(\.modelContext) private var context
    @State private var showEdit = false
    @State private var editPoint: Measurement?
    @State private var deletePoint: Measurement?
    @State private var error: String?

    private var forecast: ForecastResult { ForecastEngine.calculate(session: session) }
    private var points: [(Date, Int)] {
        [(session.startTime, session.initialAcceptedItems)] +
        session.sortedMeasurements.map { ($0.timestamp, $0.acceptedItems) }
    }
    private var maxRate: Double {
        zip(points, points.dropFirst()).compactMap { a, b -> Double? in
            let elapsed = b.0.timeIntervalSince(a.0)
            return elapsed >= 180 ? Double(b.1 - a.1) * 60 / elapsed : nil
        }.max() ?? 0
    }

    var body: some View {
        List {
            Section("Статистика") {
                LabeledContent("Начало", value: session.startTime.formatted())
                LabeledContent("Последний замер", value: session.lastTime.formatted())
                LabeledContent("Отправления", value: "\(session.acceptedNow) / \(session.totalItems)")
                LabeledContent("Длительность", value: formattedDuration(session.lastTime.timeIntervalSince(session.startTime)))
                LabeledContent("Средний темп", value: formattedRate(forecast.overallRate))
                LabeledContent("Максимальный темп", value: formattedRate(maxRate))
                LabeledContent("Замеров", value: "\(session.measurements.count)")
                if let cargo = session.cargoPlaces { LabeledContent("Грузовых мест", value: "\(cargo)") }
                if let label = session.shipmentLabel { LabeledContent("Перевозка", value: label) }
            }
            Section("Прогресс") {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Время", point.0), y: .value("Принято", point.1))
                        PointMark(x: .value("Время", point.0), y: .value("Принято", point.1))
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("График принятых отправлений")
            }
            Section("История замеров") {
                ForEach(session.sortedMeasurements) { point in
                    Button {
                        editPoint = point
                    } label: {
                        HStack {
                            Text(point.timestamp.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text("\(point.acceptedItems) / \(session.totalItems)")
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button("Удалить", role: .destructive) { deletePoint = point }
                    }
                }
            }
            if !session.teamChanges.isEmpty {
                Section("Состав команды") {
                    ForEach(session.teamChanges.sorted { $0.timestamp < $1.timestamp }) { event in
                        Text("\(event.timestamp.formatted(date: .abbreviated, time: .shortened)): \(event.previousWorkers) → \(event.workerCount) сотрудников")
                    }
                }
            }
        }
        .navigationTitle("Приёмка")
        .toolbar { Button("Изменить") { showEdit = true } }
        .sheet(isPresented: $showEdit) { EditSessionView(session: session) }
        .sheet(item: $editPoint) { point in EditMeasurementView(session: session, point: point) }
        .confirmationDialog("Удалить замер?", isPresented: Binding(
            get: { deletePoint != nil }, set: { if !$0 { deletePoint = nil } }
        )) {
            Button("Удалить", role: .destructive) { deleteMeasurement() }
        } message: {
            Text("Прогноз и график будут пересчитаны.")
        }
        .alert("Ошибка", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("ОК") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func deleteMeasurement() {
        guard let point = deletePoint else { return }
        if session.isCompleted && point.id == session.sortedMeasurements.last?.id {
            error = "Чтобы изменить итог, сначала открой редактирование приёмки."
            deletePoint = nil
            return
        }
        // A team event and its corresponding progress point form one logical record.
        let associated = session.teamChanges.filter { $0.timestamp == point.timestamp }
        session.measurements.removeAll { $0.id == point.id }
        session.teamChanges.removeAll { event in associated.contains { $0.id == event.id } }
        do { try context.save() }
        catch { self.error = "Не удалось удалить замер: \(error.localizedDescription)" }
        deletePoint = nil
    }
}

struct EditSessionView: View {
    @Bindable var session: IntakeSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var start: Date = .now
    @State private var total = ""
    @State private var initial = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Начало", selection: $start, in: ...Date.now)
                TextField("Принято в начале", text: $initial).keyboardType(.numberPad)
                TextField("Всего отправлений", text: $total).keyboardType(.numberPad)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Сохранить") { submit() }.buttonStyle(.borderedProminent)
            }
            .navigationTitle("Исправить приёмку")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear {
                start = session.startTime
                total = "\(session.totalItems)"
                initial = "\(session.initialAcceptedItems)"
            }
        }
    }

    private func submit() {
        guard let newTotal = Int(total), let newInitial = Int(initial) else {
            error = "Введи целые числа."; return
        }
        do {
            try IntakeValidator.timeline(start: start, initial: newInitial, total: newTotal,
                                         points: session.measurements.map { ($0.timestamp, $0.acceptedItems) })
            session.startTime = start
            session.totalItems = newTotal
            session.initialAcceptedItems = newInitial
            if session.isCompleted && session.acceptedNow < newTotal {
                session.isCompleted = false
                session.completedAt = nil
            }
            try context.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct EditMeasurementView: View {
    let session: IntakeSession
    @Bindable var point: Measurement
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var time: Date = .now
    @State private var count = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Время", selection: $time, in: session.startTime...Date.now)
                TextField("Принято", text: $count).keyboardType(.numberPad)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Сохранить") { submit() }.buttonStyle(.borderedProminent)
            }
            .navigationTitle("Исправить замер")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear { time = point.timestamp; count = "\(point.acceptedItems)" }
        }
    }

    private func submit() {
        guard let value = Int(count) else { error = "Введи целое число."; return }
        if session.teamChanges.contains(where: { $0.timestamp == point.timestamp }) {
            error = "Замер смены команды нельзя исправить отдельно. Удали событие и добавь его заново."
            return
        }
        let candidate = session.measurements.map { item in
            (item.id == point.id ? time : item.timestamp, item.id == point.id ? value : item.acceptedItems)
        }
        do {
            try IntakeValidator.timeline(start: session.startTime, initial: session.initialAcceptedItems,
                                         total: session.totalItems, points: candidate)
            if session.isCompleted && point.id == session.sortedMeasurements.last?.id && value < session.totalItems {
                session.isCompleted = false
                session.completedAt = nil
            } else if session.isCompleted && point.id == session.sortedMeasurements.last?.id {
                session.completedAt = time
            }
            point.timestamp = time
            point.acceptedItems = value
            try context.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    @AppStorage("automaticTime") private var automaticTime = true
    @AppStorage("forecastMethod") private var method = ForecastMethod.smoothed.rawValue
    @AppStorage("theme") private var theme = "system"
    @AppStorage("showRange") private var showRange = true
    @AppStorage("showCurrent") private var showCurrent = true
    @AppStorage("showOverall") private var showOverall = true

    var body: some View {
        Form {
            Section("Замеры") {
                Toggle("Текущее время", isOn: $automaticTime)
                Text("Время замера берётся при сохранении.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Прогноз") {
                Picker("Метод", selection: $method) {
                    ForEach(ForecastMethod.allCases) { method in
                        Text(method.title).tag(method.rawValue)
                    }
                }
            }
            Section("Интерфейс") {
                Picker("Тема", selection: $theme) {
                    Text("Системная").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                Toggle("Показывать диапазон", isOn: $showRange)
                Toggle("Показывать текущий темп", isOn: $showCurrent)
                Toggle("Показывать средний темп", isOn: $showOverall)
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("Gazon · версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}

private func formattedDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(minutes) мин"
}

private func formattedRate(_ value: Double) -> String {
    String(format: "%.2f отправления/мин", value)
}
