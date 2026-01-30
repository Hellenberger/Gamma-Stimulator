//
//  SleepStimulationControllerDelegate.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 4/14/25.
//


import Foundation
import UIKit


protocol SleepStimulationControllerDelegate: AnyObject {
    // Called when stimulation should start
    func startStimulation(duration: TimeInterval)
    
    // Called when stimulation should stop
    func stopStimulation()
    
    // Called to update UI with current sleep state
    func didUpdateSleepState(stage: SleepStage, description: String)
}
