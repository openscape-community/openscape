//
//  BoseFramesMotionManager.swift
//  Soundscape
//
//  Created by Niklas Mellegård on 2024-03-06.
//  Copyright © 2024 Soundscape community. 
//  Licensed under the MIT License.
//

import Foundation
import Combine


extension Notification.Name {
    static let boseFramesDeviceConnected = Notification.Name("GDABoseFramesConnected")
    static let boseFramesDeviceConnectionFailed = Notification.Name("GDABoseFramesConnectionFailed")
}

import Foundation
enum BoseFramesMotionManagerStatus: Int, Equatable, Comparable {
    /// unknown: Status unknown. Inital state before attampting any connection. `bleBoseFrames` is probably nil
    case unknown
    
    /// disconnected:  The manager has been created but `bleBoseFrames` is likely nil. Either we have yet to discover the BLE device or it has been explicitly disconnected
    case disconnected
    
    /// connecting: Connection (pairing) with the device has started. `bleBoseFrames` may still be nil (it will be created as part of the `connecting`process)
    case connecting
 
    /// ready: The device is ready to use
    case ready

    static func < (lhs: BoseFramesMotionManagerStatus, rhs: BoseFramesMotionManagerStatus) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

class BoseFramesMotionManager: NSObject {

    static let DEVICE_MODEL_NAME: String = GDLocalizationUnnecessary("Bose Frames (Rondo)")
        
    // MARK: Attributes
    private let queue: OperationQueue
    private var bleBoseFrames: BoseFramesBLEDevice?
    private var connectionTimer: Timer?
    private let connectionTimeOutSeconds: Double = 30.0
    
    private(set) var status: CurrentValueSubject<BoseFramesMotionManagerStatus, Never>
    
    // MARK: Device attributes
    let model = BoseFramesMotionManager.DEVICE_MODEL_NAME
    let type: DeviceType = .boseFramesRondo
    var isFirstConnection: Bool {
        get {
            guard let dev = bleBoseFrames else {return true}
            return dev.isFirstConnection
        }
    }
    
    // MARK: CalibratableDevice
    /// Threshold for accuracy estimation. Value above this indicates uncalibrated device
    private let accuracy_calibration_required_threshold: Double = 28.0
    private var accuracyRingBuffer = [Double](repeating: 100.0, count: 10) // Collect 10 latest values for averaging accuracy
    private var accuracyRingBufferPosition: Int = 0
    private var _calibrationOverridden: Bool
    private(set) var calibrationStateObservable: CurrentValueSubject<DeviceCalibrationState, Never>
    private weak var _deviceDelegate: DeviceDelegate?
    
    
    // MARK: UserHeadingProvider attributes
    /// Create a dummy Id for this device as it will not get its ID until connected.
    /// First, the `Device` protocol requires a non-optional id.
    /// Second, DeviceManager initiates the object with stored id and name, which may be used for reconnection (dunno, havn't looked... sånt
    private var _idDummy: UUID
    private var _nameDummy: String // D,o
    private weak var _headingDelegate: UserHeadingProviderDelegate?
    var _accuracy = 10000.0 // Just a very high value... Will adjust when we start getting updates
    
    
    
    // MARK: Initializers
    convenience init(id: UUID, name: String) {
        self.init()
        self._idDummy = id
        self._nameDummy = name
    }
    
    override init() {
        self._idDummy = UUID()
        self._nameDummy = ""
        queue = OperationQueue()
        queue.name = "BoseMotionUpdatesQueue"
        queue.qualityOfService = .userInteractive
        status = .init(.unknown)
        
        calibrationStateObservable = .init(.needsCalibrating)
        _calibrationOverridden = false
        
        super.init()
    }
}



// MARK: CalibratableDevice
extension BoseFramesMotionManager: CalibratableDevice {
        var isConnected: Bool {
        if let boseDevice = bleBoseFrames  {
            return boseDevice.state == .ready
        }
        else {
            return false
        }
    }
    
    
    var name: String {
        if let dev = bleBoseFrames, let name = dev.name {
            return name
        } else {
            return _nameDummy
        }
    }
    
    /// Return the identifier for the peripheral. This value is valid only whenthe device is ready and will return a dummy UUID if called before init has finished
    var id: UUID {
        if let dev = bleBoseFrames {
            return dev.uuid
        } else {
            return _idDummy
        }
    }
    
    var calibrationState: DeviceCalibrationState {
        return self.calibrationStateObservable.value
    }
  
    
    var calibrationOverriden: Bool {
        get {
            return self._calibrationOverridden
        }
        set (newValue) {
            self._calibrationOverridden = newValue
        }
    }
    
    var deviceDelegate: DeviceDelegate? {
        get {
            return self._deviceDelegate
        }
        set (newDelegate) {
            self._deviceDelegate = newDelegate
        }
    }
    
    
    static func setupDevice(callback: @escaping DeviceCompletionHandler) {
        GDLogHeadphoneMotionInfo("Bose: SetupDevice")
        let device = BoseFramesMotionManager()

        callback(.success(device))
        
        device.connect()
    }
    
    func connect() {
               
        guard bleBoseFrames == nil else {
            GDLogHeadphoneMotionInfo("Bose: Connecting Bose Frames, but they are already connected.")
            return
        }
        
        AppContext.shared.bleManager.startScan(for: BoseFramesBLEDevice.self, delegate: self)
        status.value = .connecting
        
        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeOutSeconds, repeats: false) {timer in
            self.queue.addOperation {
                GDLogHeadphoneMotionError("Bose: Connection timed out!")

                self.connectionTimer?.invalidate()
                self.connectionTimer = nil

                AppContext.shared.bleManager.stopScan()
                self.status.value = .disconnected

                NotificationCenter.default.post(name: Notification.Name.boseFramesDeviceConnectionFailed, object: nil)
                
                self.deviceDelegate?.didFailToConnectDevice(self, error: DeviceError.failedConnection)
            }
        }
    }
    
    func disconnect() {
        GDLogHeadphoneMotionInfo("Bose: Disconnect called")
        connectionTimer?.invalidate()
        connectionTimer = nil
    
        status.value = .disconnected
        stopUserHeadingUpdates()
        if (self.calibrationState != .calibrated) {
            NotificationCenter.default.post(name: Notification.Name.ARHeadsetCalibrationCancelled, object: nil)
        }
        bleBoseFrames = nil
        deviceDelegate?.didDisconnectDevice(self)
    }
}

// MARK: UserHeadingProvider
extension BoseFramesMotionManager: UserHeadingProvider {
    var headingDelegate: UserHeadingProviderDelegate? {
        get {
            return self._headingDelegate
        }
        set (newDelegate) {
            self._headingDelegate = newDelegate
        }
    }
    
    var accuracy: Double {
        return self._accuracy
    }
    
    func startUserHeadingUpdates() {
        guard let boseDevice = bleBoseFrames, boseDevice.state == .ready
        else {
            GDLogHeadphoneMotionError("Bose: Attemped to start heading updates, but the device was not ready")
            return
        }
        
        boseDevice.headingUpdateDelegate = self
        boseDevice.startHeadTracking()
    }
    
    func stopUserHeadingUpdates() {
        guard let boseDevice = bleBoseFrames, boseDevice.state == .ready
        else {
            GDLogHeadphoneMotionError("Bose: Attempted to stop heading updates, but the device was not ready")
            return
        }

        boseDevice.headingUpdateDelegate = nil
        boseDevice.stopHeadTracking()
    }
}

extension BoseFramesMotionManager: BoseHeadingUpdateDelegate {

    func onHeadingUpdate(newHeading: HeadingValue!) {
        let previousCalibrationState = calibrationState
        
        // Calculate a rolling average of accuracy to avoid jitters in the UI
        accuracyRingBuffer[accuracyRingBufferPosition] = newHeading.accuracy ?? 100.0 // If missing, just default to something higher than "calibrated"
        accuracyRingBufferPosition = (accuracyRingBufferPosition + 1) % 10
        let averageAccuracy = accuracyRingBuffer.mean()!
        self._accuracy = averageAccuracy
        GDLogHeadphoneMotionVerbose("Bose: Received heading update: \(newHeading.value), snapshot accuracy: \(newHeading.accuracy), calculated accuracy: \(_accuracy) | \(accuracyRingBuffer)")

        // Needs calibration?
        if averageAccuracy < self.accuracy_calibration_required_threshold {
            if previousCalibrationState != .calibrated {
                GDLogHeadphoneMotionInfo("Bose: Done calibrating (\(_accuracy)!")
                calibrationStateObservable.value = .calibrated
                queue.addOperation {
                    NotificationCenter.default.post(name: Notification.Name.ARHeadsetCalibrationDidFinish, object: nil)
                    AppContext.process(HeadsetCalibrationEvent(self.name, deviceType: .boseFramesRondo, callout: "", state: .calibrated))
                }
            }
            
        } else {
            if previousCalibrationState == .calibrated {
                GDLogHeadphoneMotionInfo("Bose: Needs calibration  (\(_accuracy)!")
                calibrationStateObservable.value = .needsCalibrating
                
            } else if previousCalibrationState == .needsCalibrating {
                GDLogHeadphoneMotionInfo("Bose: Start calibrating (\(_accuracy)!")
                calibrationStateObservable.value = .calibrating
                queue.addOperation {
                    NotificationCenter.default.post(name: Notification.Name.ARHeadsetCalibrationDidStart, object: nil)
                    AppContext.process(HeadsetCalibrationEvent(self.name, deviceType: .boseFramesRondo, callout: "", state: .calibrating))
                }
            }
        }

        if(_headingDelegate == nil){
            GDLogHeadphoneMotionError("Bose: No HeadingUpdateDelegate!!!")
        }
        OperationQueue.main.addOperation { [weak self] in
            guard let `self` = self else {
                return
            }
            
            queue.addOperation {
                self._headingDelegate?.userHeadingProvider(self, didUpdateUserHeading: newHeading)
            }

        }
    }
}

extension BoseFramesMotionManager: BLEManagerScanDelegate {
    
    internal func onDeviceStateChanged(_ device: BLEDevice) {
        /// State change is monitored on the `BoseFramesBLEDevice.boseState` variable
    }
    
    internal func onDeviceNameChanged(_ device: BLEDevice, _ name: String) {
        // no-op
    }
    /// Called when bleManager has discovered devices.
    internal func onDevicesChanged(_ discovered: [BLEDevice]) {
        
        guard bleBoseFrames == nil else {return}
        
        for i in 0..<discovered.count {
            if let device  = discovered[i] as? BoseFramesBLEDevice {
                GDLogHeadphoneMotionInfo("Bose: BLEManager did notify about a discovered Bose device. Chaching a reference and listen to state changes")
                AppContext.shared.bleManager.stopScan()
                self.bleBoseFrames = device
                device.stateDidChangeDelegate = self
                if(self.status.value == .unknown) {
                    self.status.value = .disconnected
                }
                break
            }
        }
    }
}


extension BoseFramesMotionManager: BoseBLEStateChangeDelegate {
    func onBoseDeviceStateChange(oldState: BLEDeviceState, newState: BLEDeviceState) {
        let oldManagerStatus = self.status.value
        
        switch newState {
        case .unknown:
            GDLogHeadphoneMotionInfo("Bose: BLEDevice state is unknown")
            self.status.value = .unknown
            
        case .disconnecting:
            GDLogHeadphoneMotionInfo("Bose: BLEDevice state is disconnecting")
            
        case .disconnected:
            GDLogHeadphoneMotionInfo("Bose: BLEDevice is .disconnected")
            self.status.value = .disconnected
            /// Was connected, signal that we just disconnected
            if (oldManagerStatus > .disconnected) {
                self.disconnect()
                AppContext.process(HeadsetConnectionEvent(BoseFramesMotionManager.DEVICE_MODEL_NAME, state: .disconnected))
            }

        case .initializing:
            GDLogHeadphoneMotionInfo("Bose: BLEDevice is connecting")
            AppContext.shared.bleManager.stopScan()
            self.status.value = .connecting

        case .ready:
            GDLogHeadphoneMotionInfo("Bose: BLEDevice is ready")
            connectionTimer?.invalidate()
            connectionTimer = nil

            NotificationCenter.default.post(name: Notification.Name.boseFramesDeviceConnected, object: nil)
            AppContext.process(HeadsetConnectionEvent(BoseFramesMotionManager.DEVICE_MODEL_NAME, state: isFirstConnection ? .firstConnection : .reconnected))
            
            self.status.value = .ready
            self.deviceDelegate?.didConnectDevice(self)
        }
    }
}
