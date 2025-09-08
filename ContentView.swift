//
//  ContentView.swift
//  Scream O Clock
//
//  Created by Tyler Zacharias on 9/4/25.
//

import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Model

enum Status { case onSet, meal, offSet }

struct Slot: Equatable {
    let start: Date
    let end: Date
    let a: Status
    let b: Status
    let c: Status
}

// MARK: - Schedule builder

func buildTodaySlots(now: Date = Date()) -> [Slot] {
    func t(_ hour12: Int, _ minute: Int, _ isPM: Bool) -> Date {
        var comps = Calendar.current.dateComponents([.year,.month,.day], from: now)
        var hour24 = hour12 % 12 + (isPM ? 12 : 0)
        if hour12 == 12 && !isPM { hour24 = 0 }   // 12 AM
        if hour12 == 12 && isPM  { hour24 = 12 }  // 12 PM
        comps.hour = hour24; comps.minute = minute; comps.second = 0
        return Calendar.current.date(from: comps)!
    }
    func s(_ start: Date, _ a: Status, _ b: Status, _ c: Status) -> Slot {
        Slot(start: start, end: start.addingTimeInterval(20*60), a: a, b: b, c: c)
    }

    return [
        s(t(7,  0, true),  .onSet, .onSet, .offSet),
        s(t(7, 20, true),  .onSet, .offSet,  .onSet),
        s(t(7, 40, true),  .meal,  .onSet, .onSet),
        s(t(8,  0, true),  .meal,  .onSet, .onSet),
        s(t(8, 20, true),  .onSet, .onSet, .offSet),
        s(t(8, 40, true),  .onSet, .meal,  .onSet),
        s(t(9,  0, true),  .onSet, .meal,  .onSet),
        s(t(9, 20, true),  .offSet,  .onSet, .onSet),
        s(t(9, 40, true),  .onSet, .onSet, .meal),
        s(t(10, 0, true),  .onSet, .onSet, .meal),
        s(t(10,20, true),  .onSet, .offSet,  .onSet),
        s(t(10,40, true),  .offSet,  .onSet, .onSet),
        s(t(11,0, true),   .onSet, .onSet, .offSet),
        s(t(11,20, true),  .onSet, .offSet,  .onSet),
        s(t(11,40, true),  .offSet,  .onSet, .onSet),
        s(t(12,0, false),  .onSet, .onSet, .offSet),  // 12:00 AM
        s(t(12,20,false),  .onSet, .offSet,  .onSet), // 12:20 AM
        s(t(12,40,false),  .offSet, .onSet, .onSet),
        s(t(1, 0, false),  .offSet, .offSet, .offSet),
    ]
}

// MARK: - Helpers

func names(with status: Status, in slot: Slot) -> String {
    var list: [String] = []
    if slot.a == status { list.append("A") }
    if slot.b == status { list.append("B") }
    if slot.c == status { list.append("C") }
    return list.joined(separator: " & ")
}

func currentSlot(now: Date, slots: [Slot]) -> Slot? {
    slots.first { now >= $0.start && now < $0.end }
}

func nextBoundary(now: Date, slots: [Slot]) -> Slot? {
    slots.first { $0.start > now }
}

func prettyClock(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0
        ? String(format: "%02d:%02d:%02d", h, m, s)
        : String(format: "%02d:%02d", m, s)
}

func timeString(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f.string(from: date)
}

// Treat 12:00–1:59 AM as "last night" so 6/7 PM anchors still map to the prior evening.
func eventDay(_ now: Date) -> Date {
    if Calendar.current.component(.hour, from: now) < 2 {
        return Calendar.current.date(byAdding: .day, value: -1, to: now)!
    }
    return now
}

func eventDayAt(_ now: Date, hour24: Int, minute: Int) -> Date {
    let base = eventDay(now)
    var comps = Calendar.current.dateComponents([.year,.month,.day], from: base)
    comps.hour = hour24; comps.minute = minute; comps.second = 0
    return Calendar.current.date(from: comps)!
}

// End cutoff (1:00 AM) on the correct day:
// - Daytime/evening: next 1:00 AM
// - After midnight: today 1:00 AM
func calculateEndTime(_ now: Date) -> Date {
    var comps = Calendar.current.dateComponents([.year,.month,.day], from: now)
    comps.hour = 1; comps.minute = 0; comps.second = 0
    var end = Calendar.current.date(from: comps)!
    if Calendar.current.component(.hour, from: now) >= 2 {
        end = Calendar.current.date(byAdding: .day, value: 1, to: end)!
    }
    return end
}

// Text used in notifications
func lineForSlot(_ s: Slot) -> String {
    var parts: [String] = []
    let on   = names(with: .onSet, in: s)
    let meal = names(with: .meal, in: s)
    let off  = names(with: .offSet, in: s)
    if !on.isEmpty   { parts.append("\(on) ON SET") }
    if !meal.isEmpty { parts.append("\(meal) on Meal") }
    if !off.isEmpty  { parts.append("\(off) Off Set") }
    return parts.joined(separator: " · ")
}

func next3AM(after date: Date) -> Date {
    var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
    comps.hour = 3; comps.minute = 0; comps.second = 0
    let today3 = Calendar.current.date(from: comps)!
    return date < today3
        ? today3
        : Calendar.current.date(byAdding: .day, value: 1, to: today3)!
}

func showStartTime(for now: Date) -> Date {
    eventDayAt(now, hour24: 19, minute: 0) // 7:00 PM local
}

// MARK: - Notifications

final class NotificationManager: ObservableObject {
    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleAll(for slots: [Slot], now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        // Pre-show "Event starts" notification at 7:00 PM
        let start = showStartTime(for: now)
        if start > now {
            let content = UNMutableNotificationContent()
            content.title = "Event starting"
            content.body  = "The show is kicking off. Get ready!"
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: start)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            center.add(UNNotificationRequest(identifier: "event-start", content: content, trigger: trigger))
        }

        for s in slots where s.start > now {
            let content = UNMutableNotificationContent()
            content.title = "Rotation"
            content.body  = lineForSlot(s)
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: s.start)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "rotation-\(Int(s.start.timeIntervalSince1970))"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        // Final "Event closed" ping at 1:00 AM
        let close = calculateEndTime(now)
        if close > now {
            let content = UNMutableNotificationContent()
            content.title = "Event closed"
            content.body  = "Great job everyone! FEED THE FEAR!! NOURISH THE TERROR!!"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: close)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "event-closed", content: content, trigger: trigger))
        }
    }
}

// MARK: - View

struct ContentView: View {
    @EnvironmentObject var notifier: NotificationManager
    @AppStorage("notificationsArmed") private var notificationsArmed: Bool = false
    @AppStorage("notificationsResetAt") private var notificationsResetAt: Double = 0 // timeIntervalSince1970
    @Environment(\.scenePhase) private var scenePhase
    
    
    
    @State private var slots: [Slot] = buildTodaySlots()
    @State private var now = Date()
    @State private var lastSlot: Slot? = nil
    @State private var showResetBanner = false
    @StateObject private var haptics = HapticsManager()
    
    private let lineSpacing: CGFloat = 20
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        let callTime  = eventDayAt(now, hour24: 18, minute: 0)
        let startTime = eventDayAt(now, hour24: 19, minute: 0)
        let endTime   = calculateEndTime(now)
        
        let active    = currentSlot(now: now, slots: slots)
        let next      = nextBoundary(now: now, slots: slots)
        
        NavigationView {
            ZStack {
                // ---- Dark gradient background
                LinearGradient(
                    colors: [Color.black, Color(red: 0.06, green: 0.08, blue: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // ---- Main content, nudged toward top
                VStack {
                    Spacer() // push content to center
                    
                    Group {
                        if now > endTime {
                            postShowView
                        } else if now < startTime {
                            preShowView(now: now, callTime: callTime, startTime: startTime)
                        } else {
                            scheduleView(active: active, next: next)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                }
            }
            // Banner as an overlay so it's part of the view chain
            .overlay(alignment: .top) {
                if showResetBanner {
                    Text("Schedule reset. Notifications disarmed.")
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: showResetBanner)
                }
            }
            .navigationTitle("HOS Rotations")
            .navigationBarTitleDisplayMode(.inline)   // <- centers title on iPhone
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        resetSchedule()
                    } label: {
                        Label("Reset Schedule", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset Schedule (disarm notifications)")
                }
            }
            // ---- Bottom button pinned to safe area
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        notifier.scheduleAll(for: slots, now: now)
                        notificationsArmed = true
                        
                        // schedule daily reset moment
                        let resetAt = next3AM(after: now)
                        notificationsResetAt = resetAt.timeIntervalSince1970
                        
                        #if canImport(UIKit)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        #endif
                    } label: {
                        Label(
                            notificationsArmed ? "Notifications armed" : "Arm notifications for tonight",
                            systemImage: notificationsArmed ? "checkmark.seal.fill" : "bell.badge"
                        )
                        .font(.headline)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .animation(.easeInOut, value: notificationsArmed)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 10)
                .background(.black.opacity(0.25)) // subtle divider from content
            }
        }
        .onReceive(timer) { t in
            now = t
            checkDailyReset(now: now)
            let s = currentSlot(now: now, slots: slots)
            if s != lastSlot {
                // Foreground: give a longer, stronger rumble when the rotation changes
                haptics.triplePulse()
                lastSlot = s
            }
            
            // Rebuild near 2:00 AM to roll the event day window forward
            if Calendar.current.component(.hour, from: now) == 2 &&
                Calendar.current.component(.minute, from: now) == 0 {
                slots = buildTodaySlots(now: now)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkDailyReset(now: Date())
            }
        }
    }
    
    // MARK: - Subviews
    
    var postShowView: some View {
        VStack(spacing: lineSpacing) {
            Text("FEED THE FEAR!! NOURISH THE TERROR!!")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Event closed! Great job everyone!")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    func preShowView(now: Date, callTime: Date, startTime: Date) -> some View {
        VStack(spacing: lineSpacing) {
            if now < callTime {
                Text("Be at venue in").font(.title3)
                Text(prettyClock(callTime.timeIntervalSince(now)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Call time: \(timeString(callTime))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Event starts in").font(.title3)
                Text(prettyClock(startTime.timeIntervalSince(now)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Show time: \(timeString(startTime))")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    func scheduleView(active: Slot?, next: Slot?) -> some View {
        VStack(spacing: lineSpacing) {
            if let s = active {
                Text("\(timeString(s.start)) – \(timeString(s.end))")
                    .foregroundStyle(.secondary)
                
                let on = names(with: .onSet, in: s)
                Text(on.isEmpty ? "No one is on set" : "\(on) are ON SET")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                
                if !names(with: .meal, in: s).isEmpty {
                    Text("\(names(with: .meal, in: s)) on Meal")
                        .font(.title3)
                }
                if !names(with: .offSet, in: s).isEmpty {
                    Text("\(names(with: .offSet, in: s)) Off Set")
                        .font(.title3)
                }
                
                VStack(spacing: 4) {
                    Text("Next rotation in \(prettyClock(s.end.timeIntervalSince(now)))")
                }
                .padding(.top, 8)
            } else {
                Text("No active slot right now").font(.title3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Reset / Daily reset
    
    func checkDailyReset(now: Date) {
        guard notificationsArmed else { return }
        let resetAt = Date(timeIntervalSince1970: notificationsResetAt)
        if now >= resetAt {
            notificationsArmed = false
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            notificationsResetAt = next3AM(after: now).timeIntervalSince1970
        }
    }
    
    func resetSchedule() {
        // Rebuild tonight’s slots fresh
        slots = buildTodaySlots(now: Date())
        
        // Disarm notifications: clear pending + delivered
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        // Flip your UI state
        notificationsArmed = false
        notificationsResetAt = 0
        
        // Haptic: “warning” or “success”—your call
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
        
        // Show a brief confirmation banner
        showResetBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showResetBanner = false
        }
    }
}
