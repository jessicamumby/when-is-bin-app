import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The background re-check of the saved schedule runs in a headless
    // engine, which needs the storage and notification plugins too.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // BGTaskScheduler only delivers a task to an app that registered its
    // handler before didFinishLaunching returned. With the UIScene lifecycle
    // the plugins register later than that, so the handler is registered
    // here. The identifier must match BackgroundRefresh.taskId and
    // BGTaskSchedulerPermittedIdentifiers; 43200s is the 12-hour recheck
    // interval, a floor that iOS stretches as it sees fit.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.jessicamumby.whenIsBinApp.scheduleRefresh",
      earliestBeginInSeconds: 43200
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
