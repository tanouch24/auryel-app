import Flutter
import UIKit
import UserNotifications
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
#endif

#if canImport(AppIntents)
import AppIntents
#endif

private let wakeAlarmPendingKey = "auryel.wake_alarm.pending"
private let wakeAlarmIDKey = "auryel.wake_alarm.alarm_id"
private let wakeAlarmSnapshotKey = "auryel.wake_alarm.snapshot"
private let wakeAlarmNotificationPrefix = "auryel.wake_alarm."

private struct WakeAlarmSnapshot: Codable, Hashable, Sendable {
  let id: String?
  let url: String?
  let title: String?
  let targetDate: String?
}

@available(iOS 17.0, *)
private struct WakeOpenAppIntent: LiveActivityIntent {
  static var title: LocalizedStringResource { "Ouvrir Auryel" }
  static var openAppWhenRun: Bool { true }

  func perform() async throws -> some IntentResult {
    UserDefaults.standard.set(true, forKey: wakeAlarmPendingKey)
    return .result()
  }
}

@available(iOS 17.0, *)
private struct WakeStopIntent: LiveActivityIntent {
  static var title: LocalizedStringResource { "Éteindre le réveil" }
  static var openAppWhenRun: Bool { true }

  func perform() async throws -> some IntentResult {
    UserDefaults.standard.set(true, forKey: wakeAlarmPendingKey)
    return .result()
  }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct AuryelAlarmMetadata: AlarmMetadata {
  let videoID: String?
  let videoURL: String?
  let videoTitle: String?
  let targetDate: String?
}
#endif

private final class WakeAlarmCoordinator: NSObject, UNUserNotificationCenterDelegate {
  private let defaults = UserDefaults.standard
  private var channel: FlutterMethodChannel?

  func register(with binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "auryel/wake_alarm",
      binaryMessenger: binaryMessenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    UNUserNotificationCenter.current().delegate = self
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canScheduleExactAlarms", "canUseFullScreenIntent":
      result(true)
    case "requestExactAlarmPermission", "requestFullScreenIntentPermission", "setAlarmSound":
      result(nil)
    case "saveAlarm":
      save(call, result: result)
    case "cancelAlarm":
      cancel(result: result)
    case "snoozeAlarm":
      snooze(call, result: result)
    case "stopRinging":
      stop(result: result)
    case "consumeWakeRingingLaunchDetails":
      result(consumeDetails())
    case "consumeWakeRingingLaunch":
      result(consumeDetails() != nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func save(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let enabled = args["enabled"] as? Bool ?? false
    let hour = args["hour"] as? Int ?? 7
    let minute = args["minute"] as? Int ?? 0
    let days = (args["days"] as? [Int]) ?? []
    let snapshot = WakeAlarmSnapshot(
      id: args["wakeVideoId"] as? String,
      url: args["wakeVideoUrl"] as? String,
      title: args["wakeVideoTitle"] as? String,
      targetDate: args["wakeTargetDate"] as? String
    )
    persist(snapshot)

    guard enabled else {
      cancel(result: result)
      return
    }

    if #available(iOS 26.0, *) {
      Task { @MainActor [weak self] in
        let scheduled = await self?.scheduleAlarmKit(
          hour: hour,
          minute: minute,
          days: days,
          snapshot: snapshot
        ) ?? false
        result(scheduled)
      }
    } else {
      scheduleLocalNotifications(
        hour: hour,
        minute: minute,
        days: days,
        snapshot: snapshot,
        result: result
      )
    }
  }

  private func cancel(result: @escaping FlutterResult) {
    if #available(iOS 26.0, *) {
      do {
        if let raw = defaults.string(forKey: wakeAlarmIDKey), let id = UUID(uuidString: raw) {
          try AlarmManager.shared.cancel(id: id)
        }
      } catch {
        // An already-fired or missing alarm is equivalent to cancellation.
      }
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: notificationIDs
    )
    defaults.set(false, forKey: wakeAlarmPendingKey)
    result(nil)
  }

  private func snooze(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if #available(iOS 26.0, *),
       let raw = defaults.string(forKey: wakeAlarmIDKey),
       let id = UUID(uuidString: raw) {
      do { try AlarmManager.shared.countdown(id: id) } catch { }
    } else {
      let content = UNMutableNotificationContent()
      content.title = "Réveil Auryel"
      content.body = "C'est l'heure de reprendre doucement ta journée."
      content.sound = .default
      content.userInfo = ["kind": "auryel.wake_alarm"]
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
      let request = UNNotificationRequest(
        identifier: "\(wakeAlarmNotificationPrefix)snooze",
        content: content,
        trigger: trigger
      )
      UNUserNotificationCenter.current().add(request)
    }
    result(nil)
  }

  private func stop(result: @escaping FlutterResult) {
    if #available(iOS 26.0, *),
       let raw = defaults.string(forKey: wakeAlarmIDKey),
       let id = UUID(uuidString: raw) {
      do { try AlarmManager.shared.stop(id: id) } catch { }
    }
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: notificationIDs
    )
    result(nil)
  }

  private func persist(_ snapshot: WakeAlarmSnapshot) {
    if let data = try? JSONEncoder().encode(snapshot) {
      defaults.set(data, forKey: wakeAlarmSnapshotKey)
    }
  }

  private func consumeDetails() -> [String: String?]? {
    guard defaults.bool(forKey: wakeAlarmPendingKey) else { return nil }
    defaults.set(false, forKey: wakeAlarmPendingKey)
    guard let data = defaults.data(forKey: wakeAlarmSnapshotKey),
          let snapshot = try? JSONDecoder().decode(WakeAlarmSnapshot.self, from: data)
    else { return [:] }
    return [
      "wakeVideoId": snapshot.id,
      "wakeVideoUrl": snapshot.url,
      "wakeVideoTitle": snapshot.title,
      "wakeTargetDate": snapshot.targetDate,
    ]
  }

  private var notificationIDs: [String] {
    (1...7).map { "\(wakeAlarmNotificationPrefix)\($0)" } +
      ["\(wakeAlarmNotificationPrefix)snooze"]
  }

  private func scheduleLocalNotifications(
    hour: Int,
    minute: Int,
    days: [Int],
    snapshot: WakeAlarmSnapshot,
    result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
      guard granted else { result(false); return }
      center.removePendingNotificationRequests(withIdentifiers: self?.notificationIDs ?? [])
      let selectedDays = days.isEmpty ? Array(1...7) : Array(Set(days)).sorted()
      for day in selectedDays where (1...7).contains(day) {
        let content = UNMutableNotificationContent()
        content.title = "Réveil Auryel"
        content.body = "C'est l'heure de commencer ta journée."
        content.sound = .default
        content.userInfo = [
          "kind": "auryel.wake_alarm",
          "wakeVideoId": snapshot.id as Any,
          "wakeVideoUrl": snapshot.url as Any,
          "wakeVideoTitle": snapshot.title as Any,
          "wakeTargetDate": snapshot.targetDate as Any,
        ]
        let date = DateComponents(calendar: Calendar.current, timeZone: .autoupdatingCurrent, hour: hour, minute: minute, weekday: day)
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(
          identifier: "\(wakeAlarmNotificationPrefix)\(day)",
          content: content,
          trigger: trigger
        )
        center.add(request)
      }
      result(true)
    }
  }

  @available(iOS 26.0, *)
  private func scheduleAlarmKit(
    hour: Int,
    minute: Int,
    days: [Int],
    snapshot: WakeAlarmSnapshot
  ) async -> Bool {
    do {
      let authorization = try await AlarmManager.shared.requestAuthorization()
      guard authorization == .authorized else { return false }
      if let raw = defaults.string(forKey: wakeAlarmIDKey), let oldID = UUID(uuidString: raw) {
        try? AlarmManager.shared.cancel(id: oldID)
      }
      let id = UUID()
      defaults.set(id.uuidString, forKey: wakeAlarmIDKey)
      let weekdays = (days.isEmpty ? Array(1...7) : Array(Set(days)).sorted()).compactMap(Self.weekday)
      let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(weekdays)
      let schedule = Alarm.Schedule.relative(
        .init(time: .init(hour: hour, minute: minute), repeats: recurrence)
      )
      let stop = AlarmButton(text: "Éteindre", textColor: .white, systemImageName: "stop.fill")
      let snooze = AlarmButton(text: "Répéter", textColor: .white, systemImageName: "zzz")
      let alert = AlarmPresentation.Alert(
        title: "Réveil Auryel",
        stopButton: stop,
        secondaryButton: snooze,
        secondaryButtonBehavior: .countdown
      )
      let presentation = AlarmPresentation(alert: alert)
      let metadata = AuryelAlarmMetadata(
        videoID: snapshot.id,
        videoURL: snapshot.url,
        videoTitle: snapshot.title,
        targetDate: snapshot.targetDate
      )
      let attributes = AlarmAttributes(
        presentation: presentation,
        metadata: metadata,
        tintColor: Color(red: 0.77, green: 0.62, blue: 0.28)
      )
      let configuration = AlarmManager.AlarmConfiguration(
        countdownDuration: .init(preAlert: nil, postAlert: 600),
        schedule: schedule,
        attributes: attributes,
        stopIntent: WakeStopIntent()
      )
      _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
      return true
    } catch {
      return false
    }
  }

  @available(iOS 26.0, *)
  private static func weekday(_ value: Int) -> Locale.Weekday? {
    switch value {
    case 1: return .sunday
    case 2: return .monday
    case 3: return .tuesday
    case 4: return .wednesday
    case 5: return .thursday
    case 6: return .friday
    case 7: return .saturday
    default: return nil
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.content.userInfo["kind"] as? String == "auryel.wake_alarm" {
      defaults.set(true, forKey: wakeAlarmPendingKey)
    }
    completionHandler()
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let wakeAlarmCoordinator = WakeAlarmCoordinator()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    wakeAlarmCoordinator.register(with: engineBridge.applicationRegistrar.messenger())
  }
}
