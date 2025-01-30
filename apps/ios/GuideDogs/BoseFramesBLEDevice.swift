//
//  BoseHeadTrackerTest.swift
//  Soundscape
//
//  Created by Niklas Mellegård on 2024-03-05.
//  Copyright © 2024 Soundscape community. 
//  Licensed under the MIT License.

//

import Foundation
import CoreBluetooth
import Combine

struct BOSE_FRAMES_SERVICE_CONSTANTS {
    static let CBUUID_HEADTRACKING_SERVICE: CBUUID = CBUUID(string: "FDD2")
    static let CBUUID_HEADTRACKING_CONFIG_CHARACTERISTIC: CBUUID = CBUUID(string: "5AF38AF6-000E-404B-9B46-07F77580890B")
    static let CBUUID_HEADTRACKING_DATA_CHARACTERISTIC: CBUUID = CBUUID(string: "56A72AB8-4988-4CC8-A752-FBD1D54A953D")
    static let CBUUID_HEADTRACKING_INFO_CHARACTERISTIC: CBUUID = CBUUID(string: "855CB3E7-98FF-42A6-80FC-40B32A2221C1")
}
protocol BoseBLEStateChangeDelegate {
    func onBoseDeviceStateChange(oldState: BLEDeviceState, newState: BLEDeviceState)
}

protocol BoseHeadingUpdateDelegate {
    func onHeadingUpdate(newHeading: HeadingValue!)
}

class BoseFramesBLEDevice: BaseBLEDevice {
    private static let BOSE_HEADING_UPDATE_INTERVAL: UInt16 = 40 // Valid intervals in ms: 320, 160, 80, 40, 20,

    // MARK: - BaseBLEDevice compliance
    private struct BoseSensorService: BLEDeviceService {
        static var uuid: CBUUID = BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_SERVICE
        
        static var characteristicUUIDs: [CBUUID] = [
            BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_CONFIG_CHARACTERISTIC,
            BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_DATA_CHARACTERISTIC
        ]
    }
    override class var services: [BLEDeviceService.Type] {
        get {
            return [BoseSensorService.self]
        }
    }
  
    var name: String? {
        get {
            return self.peripheral.name
        }
    }
    
    var uuid: UUID {
        get {
            return self.peripheral.identifier
        }
    }
  
    // MARK: - Attributes
    private var boseCharacteristicSensorConfig: CBCharacteristic?
    private var sensorConfig: BoseSensorConfiguration?
   
    private var boseCharacteristicSensorData: CBCharacteristic?
//    private let eventProcessor: BoseSensorDataProcessor
   
    private var isHeadtrackingStarted: Bool = false
    private(set) var isFirstConnection: Bool = true

    // MARK: Delegates
    var headingUpdateDelegate: BoseHeadingUpdateDelegate?
    var stateDidChangeDelegate: BoseBLEStateChangeDelegate?
    
    
    
    
    // MARK: - Init
    override init(peripheral: CBPeripheral, type deviceType: BLEDeviceType, delegate: BLEDeviceDelegate?) {
        super.init(peripheral: peripheral, type: deviceType, delegate: delegate)
    }
    
    required convenience init(peripheral: CBPeripheral, delegate: BLEDeviceDelegate?) {
        self.init(peripheral: peripheral, type: .headset, delegate: delegate)
    }
    
    
    // MARK: - Controls for headtracking
    func startHeadTracking() {
        guard let config = sensorConfig
        else {
            GDLogBLEError("Bose: Attempted to start headtracking, but device is not ready")
            return
        }
        guard isHeadtrackingStarted == false else {
            GDLogBLEInfo("Bose: Attempted to start headtracking, but headtracking is already started")
            return
        }
        
        config.rotationPeriod = BoseFramesBLEDevice.BOSE_HEADING_UPDATE_INTERVAL

        self.writeValueToConfig(value: config.toConfigToData())
        self.isHeadtrackingStarted = true
        isFirstConnection = false
    }
    
    func stopHeadTracking() {
        guard let config = sensorConfig, isHeadtrackingStarted == true
        else {
            GDLogBLEError("Bose: Attempted to stop headtracking, but device is not ready")
            return
        }

        config.rotationPeriod = 0
        
        self.writeValueToConfig(value: config.toConfigToData())
        self.isHeadtrackingStarted = false
    }
    
    func isHeadTrackingStarted() -> Bool {
        return self.isHeadtrackingStarted
    }
    
    internal func writeValueToConfig(value: Data){

        guard 
            self.state == .ready
        else {
            GDLogBLEError("Bose: Trying to write to config, but state != ready. Trying anyway")
            return
        }
        
        guard
            let configCharacteristic = boseCharacteristicSensorConfig
        else {
            GDLogBLEError("Bose: Trying to write to config, but is missing a reference to the config characteristic. Has the device completed setup? (current device.state: \(self.state)")
            return
        }
        
        let device = super.peripheral
        device.writeValue(value, for: configCharacteristic, type: .withResponse)
    }
    
    // MARK: - BLE Device lifecycle
    /// The device has been discovered. BaseBLEDevice will set state to .discovered if it was .unknown
    /// We will initiate connection to the Peripheral here.
    /// We should really check the advertisement data to veryfy that we have the correct Peripheral...
    internal override func onWasDiscovered(_ peripheral: CBPeripheral, advertisementData: [String : Any]) {
        let oldState = self.state

        super.onWasDiscovered(peripheral, advertisementData: advertisementData)
        let newState = self.state

        switch (oldState, newState) {
        case (.unknown, .disconnected):
            AppContext.shared.bleManager.connect(self)

        default:
            GDLogBLEInfo("Received an onWasDiscovered, but device did not transition from 'unknown to 'disconnected' perhaps already connecting? Current state: \(newState) (oldState: \(oldState))")
        }
        
        if oldState != newState {
            stateDidChangeDelegate?.onBoseDeviceStateChange(oldState: oldState, newState: newState)
        }
    }
    
    /// Peripheral was connected. BaseBLEDevice sets state to .initializing and starts to discover services
    override internal func onDidConnect(_ peripheral: CBPeripheral) {
        let oldState = self.state
        GDLogBLEInfo("Bose: onDidConnect")
        super.onDidConnect(peripheral)
        let newState = self.state
        
        if oldState != newState {
            stateDidChangeDelegate?.onBoseDeviceStateChange(oldState: oldState, newState: newState)
        }
    }
        
    /// Called from BaseBLE when services and characterstics have been discovered. BaseBLE does not change state.
    internal override func onSetupComplete() {
        GDLogBLEInfo("Bose: onSetupComplete")


        let oldState = self.state
        super.onSetupComplete()
        let newState = self.state
        
        if oldState != newState {
            stateDidChangeDelegate?.onBoseDeviceStateChange(oldState: oldState, newState: newState)
        }
    }
    
    ///  Caches relevant characteristics, requests currenct device configuration and subscribes to Heading updates
    ///  We will not call BaseBLEDevice.onConnectionComplete until we have read configuration
    internal override func onConnectionComplete() {
        
        GDLogBLEInfo("Bose: onConnectionComplete. Requesting current configuration")
        // Peripheral has services
        guard
            let services = self.peripheral.services
        else {
            GDLogBLEError("Bose: ERROR Peripheral does not have any services!")
            return
        }
        // Peripheral has the Bose service with the headtracking characteristics
        guard
            let boseService = services.first (where: {
                $0.uuid == BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_SERVICE
            })
        else {
            GDLogBLEError("Bose: ERROR Peripheral does not offer the Headtracking service!")
            return
        }
        // The service has characteristics
        guard
            let characteristics = boseService.characteristics
        else {
            GDLogBLEError("Bose: ERROR The Peripheral offer the Headtracking service but it has no characteristics!")
            return
        }
        // Peripheral has the headtracking config characteristic
        guard
            let configCharacteristic = characteristics.first (where: {
                $0.uuid == BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_CONFIG_CHARACTERISTIC
            })
        else {
            GDLogBLEError("Bose: ERROR Peripheral does not have the Headtracking config characteristic!")
            return
        }
        // Peripheral has the headtracking data characteristic
        guard
            let dataCharacteristic = characteristics.first (where: {
                $0.uuid == BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_DATA_CHARACTERISTIC
            })
        else {
            GDLogBLEError("Bose: ERROR Peripheral does not have the Headtracking data characteristic!")
            return
        }

        self.boseCharacteristicSensorConfig = configCharacteristic
        self.peripheral.readValue(for: configCharacteristic)
        
        self.boseCharacteristicSensorData = dataCharacteristic
        self.peripheral.setNotifyValue(true, for: dataCharacteristic)

        // Now, await notification of reading the config value and set new state from there
        
        
        /*
        for service in services {
            if (service.uuid == BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_SERVICE) {
                for c in service.characteristics! {
                    switch c.uuid {
                    case  BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_CONFIG_CHARACTERISTIC:
                        GDLogBLEInfo("Found Bose Config Characteristic")
                        self.boseCharacteristicSensorConfig = c
                        self.peripheral.readValue(for: c)
                        
                    case BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_DATA_CHARACTERISTIC:
                        GDLogBLEInfo("Found Bose Data Characteristic")
                        self.boseCharacteristicSensorData = c
                        self.peripheral.setNotifyValue(true, for: c)
                        continue

                    default:
                        () // Noop
                    }
                }
            }
        }
        
        guard boseCharacteristicSensorData != nil && boseCharacteristicSensorConfig != nil else {
            GDLogBLEError("Bose: onConnectionComplete ERROR. Did not find both Config and Data Characteristic. This will not work...")
            return 
        }
        */
        // Now, await response from the config charateristic and continue the flow in peripheral (_:didUpdateValue:_) when getting config data
    }
    
    /// Called from Peripheral (_:didReadCharacteristic:_)
    private func onDidReadDeviceConfig(){
        GDLogBLEInfo("Bose: onDidReadConfig")

        // Only trigger state change if we are initializing...
        guard 
            self.state == .initializing
        else {
            return
        }

        let oldState = self.state
        super.onConnectionComplete()
        let newState = self.state
        
        if oldState != newState {
            stateDidChangeDelegate?.onBoseDeviceStateChange(oldState: oldState, newState: newState)
        }
    }
    
    internal override func onWillDisconnect(_ peripheral: CBPeripheral) {
        GDLogBLEInfo("Bose: onWillDisconnect")
        let oldState = self.state
        super.onWillDisconnect(peripheral)
        let newState = self.state
        
        if oldState != newState {
            stateDidChangeDelegate?.onBoseDeviceStateChange(oldState: oldState, newState: newState)
        }
    }
    
    internal override func onDidDisconnect(_ peripheral: CBPeripheral) {
        let oldState = self.state
        super.onDidDisconnect(peripheral)
        let newState = self.state
        
        if oldState != newState {
            stateDidChangeDelegate?.onBoseDeviceStateChange(oldState: oldState, newState: newState)
        }
    }
    
    /// Called from Peripheral(_:didUpdateValueFor:_) when receiveing a new sensor data value
    private func onDidReadHeadingValue(value: Data!) {
        // No delegate listening to updates? No point in processing it...
        guard
            let delegate = headingUpdateDelegate
        else {
            GDLogBLEError("Bose: ERROR(?) No heading update delegate!")
            return
        }

        // Process Data object into a HeadValue
        let heading = BoseSensorDataProcessor.processSensorData(eventData: value)
        
        // Ensure sucess
        guard
            let h = heading
        else {
            GDLogBLEError("Bose: ERROR Failed to process sensor data into a HeadingValue!")
            return
        }
        
        delegate.onHeadingUpdate(newHeading: h)
    }
    
    // MARK: Read value
    internal override func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {

        
        guard 
            let value = characteristic.value
        else { return }
        
        switch characteristic.uuid {
        case BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_CONFIG_CHARACTERISTIC:
            GDLogBLEInfo("Bose: Read sensor config")
            sensorConfig = BoseSensorConfiguration.parseValue(data: value)

            self.onDidReadDeviceConfig()
            
        case BOSE_FRAMES_SERVICE_CONSTANTS.CBUUID_HEADTRACKING_DATA_CHARACTERISTIC:
            self.onDidReadHeadingValue(value: value)
            
        default:
            GDLogBLEVerbose("Got updated value for an unexpected characteristic: \(characteristic.uuid.uuidString) = \(characteristic.value)")
        }

        // BaseBLEDevice-implementation is a no-op
        super.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)        
    }
}



