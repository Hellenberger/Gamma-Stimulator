//
//  AppDelegate.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 3/2/24.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

//let viewController = ViewController()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        UserDefaults.standard.set(Date(), forKey: "LastBackgroundDate")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the app is about to terminate.
        // Save data if appropriate. See also applicationDidEnterBackground.
        // Release any resources that can be recreated in your session's init methods
    }



}

