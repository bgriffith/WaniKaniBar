//
//  WaniKaniBarController.swift
//  WaniKaniBar
//
//  Created by Ben Griffith on 03/05/2018.
//  Copyright © 2018 Ben Griffith. All rights reserved.
//

import Cocoa

class WaniKaniBarController: NSObject, PreferencesWindowDelegate {
  let wanikaniAPI = WaniKaniAPI()
  var preferencesWindow: PreferencesWindow!
  
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  
  var availableReviews: Int = 0
  var availableLessons: Int = 0
  var nextReviewDate: TimeInterval = 0
  var lastFetch: TimeInterval = 0
  
  override init() {
    super.init()
    
    statusItem.menu = constructMenu();
    statusItem.button!.image = getIcon(hasReviews: false)
    statusItem.button!.imagePosition = NSControl.ImagePosition.imageLeft

    preferencesWindow = PreferencesWindow()
    preferencesWindow.delegate = self
    
    getStudyQueue()
  }
  
  
  func constructMenu() -> NSMenu {
    let study = NSMenuItem(title: "Study!", action: #selector(self.handleStudyClick(_:)), keyEquivalent: "");
    study.target = self;

    let update = NSMenuItem(title: "Update", action: #selector(self.handleUpdateClick(_:)), keyEquivalent: "")
    update.target = self;
    
    let preferences = NSMenuItem(title: "Preferences...", action: #selector(self.handlePreferencesClick(_:)), keyEquivalent: ",")
    preferences.target = self;
    
    let quit = NSMenuItem(title: "Quit it", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    
    let menu = NSMenu()
    menu.addItem(study)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(update)
    menu.addItem(preferences)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(quit);
  
    return menu
  }
  
  @objc func handleStudyClick(_ sender: NSMenuItem) {
    if let url = URL(string: "https://www.wanikani.com") {
      NSWorkspace.shared.open(url)
    }
  }
  
  @objc func handleUpdateClick(_ sender: NSMenuItem) {
    getStudyQueue()
  }
  
  @objc func handlePreferencesClick(_ sender: NSMenuItem) {
    preferencesWindow.showWindow(nil)
    preferencesWindow.setWindowVisible()
  }

  
  func preferencesDidUpdate() {
    getStudyQueue()
  }
  
  
//  func notifyUser(reviewCount: Int) {
//    let notification = NSUserNotification()
//    notification.title = "Reviews now available!"
//    notification.informativeText = "You have \(reviewCount) cards awaiting review."
//    notification.hasActionButton = true
//    notification.actionButtonTitle = "Review"
//    NSUserNotificationCenter.default.deliver(notification)
//    NSSound(named: NSSound.Name(rawValue: "Purr"))?.play()
//  }
  
  
  
  func getIcon(hasReviews: Bool) -> NSImage? {
    let statusIcon = NSImage(named: "available-icon")
    statusIcon?.isTemplate = !hasReviews
    
    return statusIcon
  }
  
  func getTitle(_ studyQueue: StudyQueue) -> String {
    let title = studyQueue.availableReviews > 0
      ? "\(studyQueue.availableReviews) reviews"
      : "\(self.getTimeTillNextReview(timestamp: studyQueue.nextReviewDate))"
    
    return title
  }
  
  func getNextReviewCountdown(_ studyQueue: StudyQueue) -> TimeInterval {
    return studyQueue.nextReviewDate - NSDate().timeIntervalSince1970
  }
  
  
  
  
  func getStudyQueue() {
    print("getStudyQueue")
    
    let pb = NSPasteboard.general.pasteboardItems?.first?.string(forType: .string);
    let defaults = UserDefaults.standard
    let apiKey = defaults.string(forKey: "ApiKey") ?? pb!

    guard apiKey != "" else {
      statusItem.button!.title = "Enter API key"
      return
    }

    wanikaniAPI.fetchStudyQueue(apiKey, success: { studyQueue in
      DispatchQueue.main.async {
        self.statusItem.button!.title = self.getTitle(studyQueue)
        self.statusItem.button!.image = self.getIcon(hasReviews: studyQueue.availableReviews > 0)
        
//        print(NSDate().timeIntervalSince1970)
        self.lastFetch = NSDate().timeIntervalSince1970
        
        // If nothing has changed
        if self.availableReviews == studyQueue.availableReviews
          && self.availableLessons == studyQueue.availableLessons
          && self.nextReviewDate == studyQueue.nextReviewDate {
          print("--nothing changed--\n")
          return
        }
        
        // If all reviews done, end the timer
        if self.availableReviews > 0 && studyQueue.availableReviews == 0 {
          print("all reviews done")
          self.endTimer()
        }
        
        // If next review date is updated
        if self.nextReviewDate != studyQueue.nextReviewDate {
          if self.isTimerRunner {
            print("end timer")
            self.endTimer()
          }
        }
        
        
        // Store latest data
        self.availableReviews = studyQueue.availableReviews
        self.availableLessons = studyQueue.availableLessons
        self.nextReviewDate = studyQueue.nextReviewDate
        

        
        if studyQueue.availableReviews > 0 {
          self.setupTimer(studyQueue, timeInterval: 300)
        } else {
          let countdown = Int(self.getNextReviewCountdown(studyQueue))
          guard countdown > 0 else { return }
     
          self.setupTimer(studyQueue, timeInterval: 60, countdown: countdown)
        }

        // Only want to send a notification if we're going from having no available reviews to having some
//        if studyQueue.availableReviews > 0 {
//          self.notifyUser(reviewCount: studyQueue.availableReviews)
//        }
      }
    })
  }
  

  var timer = Timer()
  var isTimerRunner: Bool = false
  var countdown: Int? = nil
  var timeInterval: Int = 60
  
  func setupTimer(_ studyQueue: StudyQueue, timeInterval: Int = 60, countdown: Int? = nil) {
    guard isTimerRunner == false else { return }
    
    self.timeInterval = timeInterval
    self.countdown = countdown
    
    print("set timer")
    
    timer = Timer.scheduledTimer(
      timeInterval: TimeInterval(timeInterval),
      target: self,
      selector: (#selector(self.updateTimer(_:))),
      userInfo: ["studyQueue": studyQueue],
      repeats: true
    )
    
    isTimerRunner = true
  }
  
  @objc func updateTimer(_ timer: Timer) {
    let data = timer.userInfo as! Dictionary<String, Any?>
    let studyQueue = data["studyQueue"] as! StudyQueue
    
    if var counter = countdown {
      if counter > 0 {
        statusItem.button?.title = getTitle(studyQueue)
        counter -= timeInterval
        countdown = counter
      }

      if counter < 0 {
        endTimer()
        getStudyQueue()
      }
      
      if (NSDate().timeIntervalSince1970 - self.lastFetch) > 900 {
        print("fetch is old")
        getStudyQueue()
      }
      
    } else {
      getStudyQueue()
    }
  }
  
  func endTimer() {
    print("end timer")
    timer.invalidate()
    isTimerRunner = false
  }
  
  func getTimeTillNextReview(timestamp: TimeInterval) -> String {
    let modifiedTimestamp = Int(timestamp - NSDate().timeIntervalSince1970)
    let time = secondsToDaysHoursMinutes(seconds: modifiedTimestamp)
    let roundedDays = getRoundedDays(time)
    let roundedHours = getRoundedHours(time)
    let roundedMinutes = getRoundedMinutes(time)
    
    if roundedDays > 0 {
      return "~\(roundedDays) day\(getMultipleSuffix(roundedDays))"
    }
    
    if roundedHours > 0 {
      return "~\(roundedHours) hour\(getMultipleSuffix(roundedHours))"
    }
    
    return "\(time.minutes < 1 ? "<" : "")\(roundedMinutes) min\(getMultipleSuffix(roundedMinutes))"
  }
  
  func isNotSingular(_ value: Int) -> Bool {
    return value > 1
  }
  
  func getMultipleSuffix(_ value: Int) -> String {
    return isNotSingular(value) ? "s" : ""
  }
}
