//
//  WCSessionStatus.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 4/20/25.
//


import Foundation

class WCSessionStatus: ObservableObject {
    @Published var connectionStatus: String = "WCSession: Waiting..."
    @Published var status: String = "Ready"
}
