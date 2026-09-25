import SwiftUI
import SwiftData
import Charts

private func clock(_ date: Date) -> String {
    date.formatted(.dateTime.day().month().hour().minute())
}

private func duration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(minutes) мин"
}

private func rate(_ value: Double?) -> String {
    guard let value else { return "Нет данных" }
    return String(format: "%.1f / мин", value)
}

private func save(_ context: ModelContext, error: Binding<String?>) {
    do { try context.save() }
    catch let caught { error.wrappedValue = "Не удалось сохранить: \(caught.localizedDescription)" }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("theme") private var theme = "system"
    @Query(sort: \IntakeSession.createdAt, order: .reverse) private var sessions: [IntakeSession]
    @State private var showNew = false
    @State private var error: String?

    private var active: IntakeSession? { sessions.first { !$0.isCompleted } }
    private var colorScheme: ColorScheme? {
        theme == "light" ? .light : theme == "dark" ? .dark : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let active {
                    ActiveIntakeView(session: active)
                } else {
                    ContentUnavailableView {
                        Label("Сегодня нет активной приёмки", systemImage: "shippingbox")
                    } description: {
                        Text("Укажи число отправлений и время начала работы.")
                    } actions: {
                        Button("Новая приёмка", systemImage: "plus") { showNew = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Gazon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { HistoryView() } label: {
                        Label("История", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink { SettingsView() } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                NewIntakeView().presentationDetents([.large])
            }
            .alert("Ошибка", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("ОК") { error = nil }
            } message: { Text(error ?? "") }
        }
        .preferredColorScheme(colorScheme)
        .tint(Color(red: 0.02, green: 0.42, blue: 0.98))
    }
}

struct NewIntakeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var start = Date.now
    @State private var accepted = ""
    @State private var total = ""
    @State private var cargo = ""
    @State private var label = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Новая приёмка")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Начало").font(.headline)
                        DatePicker("Начало", selection: $start, in: ...Date.now,
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                    HStack(alignment: .top, spacing: 12) {
                        countField("Принято", text: $accepted, placeholder: "0")
                        countField("Всего", text: $total, placeholder: "633")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Дополнительно").font(.headline)
                        TextField("Грузовых мест", text: $cargo)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("Номер перевозки", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .padding(16)
            }
            .navigationTitle("Gazon")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Начать приёмку") { create() }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .padding(16)
                    .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
        }
    }

    private func countField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func create() {
        guard let totalValue = Int(total), let acceptedValue = Int(accepted.isEmpty ? "0" : accepted),
              cargo.isEmpty || (Int(cargo) ?? 0) > 0 else {
            error = "Введи корректное количество отправлений и грузовых мест."
            return
        }
        do {
            try IntakeValidator.new(start: start, accepted: acceptedValue, total: totalValue)
            let session = IntakeSession(startTime: start, totalItems: totalValue,
                                        initialAcceptedItems: acceptedValue,
                                        cargoPlaces: Int(cargo),
                                        shipmentLabel: label.isEmpty ? nil : label)
            context.insert(session)
            try context.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ActiveIntakeView: View {
    @Bindable var session: IntakeSession
    @Environment(\.modelContext) private var context
    @AppStorage("forecastMethod") private var method = ForecastMethod.smoothed.rawValue
    @AppStorage("showRange") private var showRange = true
    @AppStorage("showCurrent") private var showCurrent = true
    @AppStorage("showOverall") private var showOverall = true
    @State private var showMeasurement = false
    @State private var showTeam = false
    @State private var error: String?

    private var result: ForecastResult {
        ForecastEngine.calculate(session: session, method: ForecastMethod(rawValue: method) ?? .smoothed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Приёмка").font(.headline).foregroundStyle(.secondary)
                    Text("\(session.acceptedNow) / \(session.totalItems)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    ProgressView(value: result.progress)
                        .tint(.accentColor)
                        .accessibilityLabel("Прогресс")
                        .accessibilityValue("\(Int((result.progress * 100).rounded())) процентов")
                    Text("\(Int((result.progress * 100).rounded()))%").font(.headline)
                    metric("Осталось", "\(result.remainingItems) отправлений")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                if result.remainingItems == 0 {
                    GroupBox("Приёмка завершена") {
                        VStack(alignment: .leading, spacing: 12) {
                            metric("Фактическое окончание", clock(session.lastTime))
                            metric("Общее время", duration(session.lastTime.timeIntervalSince(session.startTime)))
                            metric("Средний темп", rate(result.overallRate))
                        }
                    }
                    if !session.isCompleted {
                        Button("Завершить") {
                            session.isCompleted = true
                            session.completedAt = session.lastTime
                            save(context, error: $error)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    GroupBox("Прогноз") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let finish = result.estimatedFinish, finish > .now {
                                metric("Окончание", "≈ " + clock(finish))
                                if showRange, let early = result.earliestFinish, let late = result.latestFinish {
                                    metric("Ориентир", "\(clock(early)) – \(clock(late))")
                                }
                                if let remainingTime = result.remainingTime {
                                    metric("Осталось времени", "≈ " + duration(remainingTime))
                                }
                            } else if result.estimatedFinish != nil {
                                Text("Прогноз по последнему замеру устарел. Добавь новый замер.")
                            } else {
                                Text(session.teamChanges.isEmpty ? "Разгружайте приёмку. Для прогноза нужен ещё один замер." :
                                        "После смены команды нужен новый замер.")
                            }
                        }
                    }
                    if showCurrent { metric("Текущий темп", rate(result.currentRate)) }
                    if showOverall { metric("Средний темп", rate(result.overallRate)) }
                    metric("Начали", clock(session.startTime))
                    metric("Последний замер", clock(session.lastTime))
                    if let cargo = session.cargoPlaces { metric("Грузовых мест", "\(cargo)") }
                    if let label = session.shipmentLabel { metric("Перевозка", label) }
                    if result.progress >= 0.95 { Text("Почти готово").font(.headline) }
                    Button("Изменился состав команды") { showTeam = true }
                }
                NavigationLink("Подробная статистика") { IntakeDetailView(session: session) }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if result.remainingItems > 0 {
                Button { showMeasurement = true } label: {
                    Label("Замер", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showMeasurement) { AddMeasurementView(session: session) }
        .sheet(isPresented: $showTeam) { TeamChangeView(session: session) }
        .alert("Ошибка", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("ОК") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private func metric(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit()
        }
    }
}

struct AddMeasurementView: View {
    let session: IntakeSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("automaticTime") private var automaticTime = true
    @State private var value = ""
    @State private var time = Date.now
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Использовать текущее время автоматически", isOn: $automaticTime)
                if automaticTime {
                    LabeledContent("Время", value: "Сейчас")
                } else {
                    DatePicker("Время замера", selection: $time, in: session.startTime...Date.now)
                }
                HStack {
                    TextField("Принято сейчас", text: $value)
                        .keyboardType(.numberPad).focused($focused)
                    Text("/ \(session.totalItems)").foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Сохранить замер") { submit() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Новый замер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { if automaticTime { submit() } else { focused = false } }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        guard let count = Int(value) else { error = "Введи число отправлений."; return }
        let timestamp = automaticTime ? Date.now : time
        do {
            try IntakeValidator.measurement(count, at: timestamp, session: session)
            let item = Measurement(timestamp: timestamp, acceptedItems: count)
            session.measurements.append(item)
            do {
                try context.save()
                dismiss()
            } catch {
                session.measurements.removeAll { $0.id == item.id }
                self.error = "Не удалось сохранить: \(error.localizedDescription)"
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct TeamChangeView: View {
    let session: IntakeSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var workers = 2
    @State private var time = Date.now
    @State private var accepted = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Сейчас: \(workers) сотрудников", value: $workers, in: 1...30)
                DatePicker("Время изменения", selection: $time, in: session.lastTime...Date.now)
                TextField("Принято к этому моменту", text: $accepted).keyboardType(.numberPad)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Сохранить изменение") { submit() }
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Состав команды")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear {
                workers = session.teamChanges.sorted { $0.timestamp < $1.timestamp }.last?.workerCount ?? 1
                accepted = "\(session.acceptedNow)"
            }
        }
    }

    private func submit() {
        guard let count = Int(accepted) else { error = "Введи число отправлений."; return }
        do {
            try IntakeValidator.measurement(count, at: time, session: session)
            let previous = session.teamChanges.sorted { $0.timestamp < $1.timestamp }.last?.workerCount ?? 1
            let point = Measurement(timestamp: time, acceptedItems: count)
            let change = TeamChange(timestamp: time, previousWorkers: previous,
                                    workerCount: workers, acceptedItemsAtChange: count)
            session.measurements.append(point)
            session.teamChanges.append(change)
            do { try context.save(); dismiss() }
            catch {
                session.measurements.removeAll { $0.id == point.id }
                session.teamChanges.removeAll { $0.id == change.id }
                self.error = "Не удалось сохранить: \(error.localizedDescription)"
            }
        } catch { self.error = error.localizedDescription }
    }
}
