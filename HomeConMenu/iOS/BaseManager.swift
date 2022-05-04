//
//  BaseManager.swift
//  HomeMenu
//
//  Created by Yuichi Yoshida on 2022/03/06.
//
//  MIT License
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import HomeKit
import os

class BaseManager: NSObject, HMHomeManagerDelegate, HMAccessoryDelegate, mac2iOS, HMHomeDelegate {

    var homeManager: HMHomeManager?
    var ios2mac: iOS2Mac?
    
    var accessories: [AccessoryInfoProtocol] = []
    var serviceGroups: [ServiceGroupInfoProtocol] = []
    var rooms: [RoomInfoProtocol] = []
    
    func updateColor(uniqueIdentifier: UUID, value: Double) {
        guard let characteristic = self.homeManager?.getCharacteristic(with: uniqueIdentifier) else { return }
        characteristic.writeValue(value) { error in
            if let error = error {
                Logger.homeKit.error("\(error.localizedDescription)")
            }
        }
    }
    
    func reload(uniqueIdentifiers: [UUID]) {
        
        let characteristics = self.accessories
            .map({$0.services})
            .flatMap({$0})
            .map({$0.characteristics})
            .flatMap({$0})
        
        for uniqueIdentifier in uniqueIdentifiers {
            for characteristicInfo in characteristics {
                if characteristicInfo.uniqueIdentifier == uniqueIdentifier {
                    if let characteristic = characteristicInfo.characteristic as? HMCharacteristic {
                        characteristic.readValue { error in
                            if let error = error {
                                Logger.homeKit.error("\(error.localizedDescription)")
                                characteristicInfo.enable = false
                                self.ios2mac?.didUpdate(chracteristicInfo: characteristicInfo)
                            } else {
                                characteristicInfo.value = characteristic.value
                                self.ios2mac?.didUpdate(chracteristicInfo: characteristicInfo)
                                characteristicInfo.enable = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    func openCamera(uniqueIdentifier: UUID) {
        guard let accesory = self.homeManager?.getAccessory(with: uniqueIdentifier) else { return }
        guard let cameraProfile = accesory.cameraProfiles?.first else { return }
        guard cameraProfile.streamControl?.delegate == nil else { return }      // check wheter already camera view has been opened.
        
        let userActivity = NSUserActivity(activityType: "com.sonson.HomeMenu.openCamera")
        userActivity.title = "default"
        userActivity.addUserInfoEntries(from: ["uniqueIdentifier": uniqueIdentifier])
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: userActivity, options: nil, errorHandler: nil)
    }
    
    
    func toggleValue(uniqueIdentifier: UUID) {
        if let characteristic = homeManager?.getCharacteristic(with: uniqueIdentifier) {
            characteristic.readValue { error in
                if let error = error {
                    Logger.homeKit.error("\(error.localizedDescription)")
                } else {
                    if let value = characteristic.value as? NSNumber {
                        if value.intValue == 0 {
                            let newValue = Int(1)
                            characteristic.writeValue(newValue) { error in
                                if let error = error {
                                    Logger.homeKit.error("\(error.localizedDescription)")
                                } else {
                                    let charaInfo = CharacteristicInfo(characteristic: characteristic)
                                    self.ios2mac?.didUpdate(chracteristicInfo: charaInfo)
                                }
                            }
                        } else if value.intValue == 1 {
                            let newValue = Int(0)
                            characteristic.writeValue(newValue) { error in
                                if let error = error {
                                    Logger.homeKit.error("\(error.localizedDescription)")
                                } else {
                                    let charaInfo = CharacteristicInfo(characteristic: characteristic)
                                    self.ios2mac?.didUpdate(chracteristicInfo: charaInfo)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    override init() {
        super.init()
        loadPlugin()
        homeManager = HMHomeManager()
        homeManager?.delegate = self
    }
    
    func loadPlugin() {
        let bundleFile = "macOSBridge.bundle"

        guard let bundleURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent(bundleFile) else {
            Logger.app.error("Failed to create bundle URL.")
            return
        }
        guard let bundle = Bundle(url: bundleURL) else {
            Logger.app.error("Failed to load a bundle file.")
            return
        }
        guard let pluginClass = bundle.principalClass as? iOS2Mac.Type else {
            Logger.app.error("Failed to load the principalClass.")
            return
        }
        ios2mac = pluginClass.init()
        ios2mac?.iosListener = self
        Logger.app.info("iOS2Mac has been loaded.")
    }
    
    func accessoryDidUpdateServices(_ accessory: HMAccessory) {
        Logger.homeKit.info("accessoryDidUpdateServices")
    }
    
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Logger.homeKit.info("accessory:service:didUpdateValueFor:characteristic:")
        guard let obj = self.accessories.first(where: { info in
            return info.uniqueIdentifier == accessory.uniqueIdentifier
        }) else { return }
        for service in obj.services {
            for chara in service.characteristics {
                if chara.uniqueIdentifier == characteristic.uniqueIdentifier {
                    chara.value = characteristic.value
                    ios2mac?.didUpdate(chracteristicInfo: chara)
                }
            }
        }
    }
    
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        if status.contains(.restricted) {
            Logger.app.error("HomeConMenu is not authorized to access HomeKit.")
            _ = ios2mac?.openHomeKitAuthenticationError()
            let userActivity = NSUserActivity(activityType: "com.sonson.HomeMenu.LaunchView")
            userActivity.title = "default"
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: userActivity, options: nil, errorHandler: nil)
        } else {
            Logger.app.info("HomeConMenu is authorized to access HomeKit.")
        }
        ios2mac?.didUpdate()
    }
    
    func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        let info = accessory.convert2info(delegate: self)
        self.accessories.append(info)
        ios2mac?.didUpdate()
    }
    
    func home(_ home: HMHome, didRemove accessory: HMAccessory) {
        accessories.removeAll { accessoryInfo in
            accessoryInfo.uniqueIdentifier == accessory.uniqueIdentifier
        }
        ios2mac?.didUpdate()
    }
    
    func homeManagerDidUpdatePrimaryHome(_ manager: HMHomeManager) {
        Logger.homeKit.info("homeManagerDidUpdatePrimaryHome:")
    }
    
    func home(_ home: HMHome, didUnblockAccessory accessory: HMAccessory) {
        Logger.homeKit.info("home:didUnblockAccessory:")
    }
    
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Logger.homeKit.info("homeManagerDidUpdateHomes:")
        
        guard let home = manager.primaryHome else {
            Logger.app.info("Primary home has not been found.")
            let userActivity = NSUserActivity(activityType: "com.sonson.HomeMenu.LaunchView")
            userActivity.title = "default"
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: userActivity, options: nil, errorHandler: nil)
            ios2mac?.openNoHomeError()
            ios2mac?.didUpdate()
            return
        }
        home.delegate = self

        accessories = home.accessories.map({$0.convert2info(delegate: self)})
        serviceGroups = home.serviceGroups.map({ServiceGroupInfo(serviceGroup: $0)})
        rooms = home.rooms.map({ RoomInfo(name: $0.name, uniqueIdentifier: $0.uniqueIdentifier) })
        
        ios2mac?.didUpdate()

        if !UserDefaults.standard.bool(forKey: "doesNotShowLaunchViewController") {
            let userActivity = NSUserActivity(activityType: "com.sonson.HomeMenu.LaunchView")
            userActivity.title = "default"
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: userActivity, options: nil, errorHandler: nil)
        }
        ios2mac?.didUpdate()
    }
    
    func openAbout() {
        let userActivity = NSUserActivity(activityType: "com.sonson.HomeMenu.LaunchView")
        userActivity.title = "default"
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: userActivity, options: nil, errorHandler: nil)
    }
}
