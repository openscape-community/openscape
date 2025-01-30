//
//  BoseFramesReachability.swift
//  Soundscape
//
//  Created by Niklas Mellegård on 2024-03-06.
//  Copyright © 2024 Soundscape community. 
//  Licensed under the MIT License.
//

import Foundation
class BoseFramesMotionManagerReachability: DeviceReachability {
    /*
        private var boseBleDevice: BoseFramesBLEDevice? {
        get {
            return boseStateDelegate?.boseDevice
        }
    }
    */
    
    private var timer: Timer?
    private var completionHandler: ReachabilityCompletion?
    private let lock = NSLock()
    private var isActive: Bool = false
//    private var boseStateDelegate: BoseBLEStateChangeDelegate?
    
    init(){
        GDLogHeadphoneMotionInfo("[PING] BoseMotionReachability created")
  //      boseStateDelegate = BoseDeviceStateDelegate(livePingHandler: self.cleanup)
    }
    /// Dummy implementation.
    /// Redesign needed: Cannot use BLEManager as it cancells an ongoing discovery. Perhaps use coreBluetooth to see if headset is reachable?
    func ping(timeoutInterval: TimeInterval, completion: @escaping ReachabilityCompletion) {
        GDLogHeadphoneMotionInfo("Bose: [PING] returning dummy ping value...")
        return completion(true)
    }
    
    /*
    func ping(timeoutInterval: TimeInterval, completion: @escaping ReachabilityCompletion) {
        GDLogHeadphoneMotionInfo("[PING] BoseMotionReachability.ping started")
        
        guard isActive == false else {
            completion(false)
            return
        }

        isActive = true
        self.completionHandler = completion
        
        let bleManager = AppContext.shared.bleManager
        
        bleManager.startScan(for: BoseFramesBLEDevice.self, delegate: boseStateDelegate!)

        // Start timeout on main thread
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            
            GDLogHeadphoneMotionInfo("[PING] Awaiting Bose BLE connection...")
            self.timer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
                guard let `self` = self else {
                    return
                }
                
                GDLogHeadphoneMotionInfo("[PING] Scheduled timer for Bose connection did fire")
                // Timer fired before bose connected `headphoneMotionManagerDidConnect`
                self.cleanup(isReachable: false)
            }
        }
    }
    */
    private func cleanup(isReachable: Bool) {
        self.lock.lock()
        
        defer {
            self.lock.unlock()
        }
        
        GDLogHeadphoneMotionInfo("[PING] Stopping Bose motion updates...")
        
        // Stop and reset timer
        timer?.invalidate()
        timer = nil
        
//        boseStateDelegate = nil
        
        GDLogHeadphoneMotionInfo("[PING] Bose reachability: \(isReachable)")
        // Return reachability and reset
        completionHandler?(isReachable)
        completionHandler = nil
        
        // Update state
        isActive = false
    }
    
}
/*
fileprivate class BoseDeviceStateDelegate: BLEManagerScanDelegate {
    var boseDevice: BoseFramesBLEDevice?
    var pingHandler: (Bool) -> Void
    init(livePingHandler: @escaping (Bool) -> Void) {
        pingHandler = livePingHandler
    }
    
    deinit {
        // Stop and reset motion manager
        boseDevice?.stopHeadTracking()
        boseDevice = nil
    }
    
    func onDeviceStateChanged(_ device: BLEDevice) {
        if let boseDev = device as? BoseFramesBLEDevice {
            if(boseDev.state == .ready) {
                GDLogHeadphoneMotionInfo("[PING] Bose Frames are ready, starting to sample the sensor")
                boseDevice = boseDev
                AppContext.shared.bleManager.stopScan()
                boseDev.headingUpdateDelegate = self
                boseDev.startHeadTracking()
            } else {
                GDLogHeadphoneMotionInfo("[PING] Bose Frames state changed, but still not ready (\(device.state))")
            }
        }
    }
    
    func onDeviceNameChanged(_ device: BLEDevice, _ name: String) {
        
    }
    
    func onDevicesChanged(_ discovered: [BLEDevice]) {
        if boseDevice == nil  {
            for i in 0..<discovered.count {
                if(discovered[i] is BoseFramesBLEDevice) {
                    boseDevice = (discovered[i] as! BoseFramesBLEDevice)
                    boseDevice?.stateDidChangeDelegate = self
                    return
                }
            }
        }
    }
}
extension BoseDeviceStateDelegate: BoseBLEStateChangeDelegate {
    func onBoseDeviceStateChange(oldState: BLEDeviceState, newState: BLEDeviceState) {
        <#code#>
    }
    
    func onBoseDeviceReady() {
        GDLogHeadphoneMotionInfo("[PING] Bose Frames are ready (but doing nothing, as I think this was handled above)")
    }
    
    func onBoseDeviceDisconnected() {
        
    }
    
    
}
extension BoseDeviceStateDelegate: BoseHeadingUpdateDelegate {
    func onHeadingUpdate(newHeading: HeadingValue!) {
        GDLogHeadphoneMotionInfo("[PING] BoseMotionReachability received a heading update")
        self.pingHandler(true)
    }
}
*/
