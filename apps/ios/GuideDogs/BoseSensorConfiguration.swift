//
//  BoseConfiguration.swift
//  Soundscape
//
//  Created by Niklas Mellegård on 2024-03-05.
//  Copyright © 2024 Soundscape community.
//  Licensed under the MIT License.
//

import Foundation

class BoseSensorConfiguration {
    // Period is in millisecond update interval. Valid intervals:    320, 160, 80, 40, 20
    static let GYROSCOPE_ID :UInt8 = 0
    var gyroscopePeriod: UInt16 = 0

    static let ACCELEROMETER_ID:UInt8 = 1
    var accelerometerPeriod: UInt16 = 0
        
    static let ROTATION_ID:UInt8 = 2
    var rotationPeriod: UInt16 = 0
    
    static let GAME_ROTATION_ID:UInt8 = 3
    var gamerotationPeriod: UInt16 = 0
    
    static func parseValue(data: Data) -> BoseSensorConfiguration {
        let byteArray: [UInt8] = BitUtils.dataToByteArray(data: data)
        let result = BoseSensorConfiguration()
        
        result.accelerometerPeriod = BitUtils.twoBytesToUInt16(byteArray[1], byteArray[2])
        result.gyroscopePeriod = BitUtils.twoBytesToUInt16(byteArray[4], byteArray[5])
        result.rotationPeriod = BitUtils.twoBytesToUInt16(byteArray[7], byteArray[8])
        result.gamerotationPeriod = BitUtils.twoBytesToUInt16(byteArray[10], byteArray[11])
        
        return result
    }
    
    private func toByteArr<T: BinaryInteger>(endian: T, count: Int) -> [UInt8] {
        var _endian = endian
        let bytePtr = withUnsafePointer(to: &_endian) {
            $0.withMemoryRebound(to: UInt8.self, capacity: count) {
                UnsafeBufferPointer(start: $0, count: count)
            }
        }
        return [UInt8](bytePtr)
    }
    private func swapEndianess(byteArr: [UInt8]) -> [UInt8] {
        return [byteArr[1], byteArr[0]]
    }
    
    
    func toConfigToData() -> Data {
        var newConfig: Data = Data()
                
        newConfig.append(contentsOf: [BoseSensorConfiguration.ACCELEROMETER_ID])
        newConfig.append(contentsOf: swapEndianess(byteArr: toByteArr(endian: accelerometerPeriod, count: 2)))

        newConfig.append(contentsOf: [BoseSensorConfiguration.GYROSCOPE_ID])
        newConfig.append(contentsOf: swapEndianess(byteArr: toByteArr(endian: gyroscopePeriod, count: 2)))

        newConfig.append(contentsOf: [BoseSensorConfiguration.ROTATION_ID])
        newConfig.append(contentsOf: swapEndianess(byteArr: toByteArr(endian: rotationPeriod, count: 2)))
        
        newConfig.append(contentsOf: [BoseSensorConfiguration.GAME_ROTATION_ID])
        newConfig.append(contentsOf: swapEndianess(byteArr: toByteArr(endian: gamerotationPeriod, count: 2)))

        GDLogBLEInfo("Encoded new config to: \(BitUtils.dataToByteArray(data: newConfig))")
        
        return newConfig
    }
}
