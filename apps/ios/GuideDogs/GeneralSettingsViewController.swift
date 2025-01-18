//
//  GeneralSettingsViewController.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import UIKit

class GeneralSettingsViewController: UITableViewController {
    
    private enum GeneralRow: Int, CaseIterable {
        case languageAndRegion = 0
        case voice = 1
        case beaconSettings = 2
        case volumeSettings = 3
        case manageDevices = 4
        case siriShortcuts = 5
    }
    
    private static let cellIdentifiers: [GeneralRow: String] = [
        .languageAndRegion: "languageAndRegion",
        .voice: "voice",
        .beaconSettings: "beaconSettings",
        .volumeSettings: "volumeSettings",
        .manageDevices: "manageDevices",
        .siriShortcuts: "siriShortcuts"
    ]
    
    
    private static let rowDescriptions: [GeneralRow: String] = [
        .languageAndRegion: GDLocalizedString("settings.general.language_and_region"),
        .voice: GDLocalizedString("settings.general.voice"),
        .beaconSettings: GDLocalizedString("settings.general.beacon_settings"),
        .volumeSettings: GDLocalizedString("settings.general.volume_settings"),
        .manageDevices: GDLocalizedString("settings.general.manage_devices"),
        .siriShortcuts: GDLocalizedString("settings.general.siri_shortcuts")
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = GDLocalizedString("settings.section.general")
        
        // Register the default UITableViewCell class for reuse
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "languageAndRegion")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "voice")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "beaconSettings")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "volumeSettings")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "manageDevices")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "siriShortcuts")
    }


    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1 // Single section for General Settings
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return GeneralRow.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = GeneralRow(rawValue: indexPath.row) else {
            fatalError("Unexpected row in General Settings")
        }
        
        let cellIdentifier = GeneralSettingsViewController.cellIdentifiers[row] ?? "default"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        cell.textLabel?.text = GeneralSettingsViewController.rowDescriptions[row]
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let row = GeneralRow(rawValue: indexPath.row) else { return }
        navigateToDetail(for: row)
    }
    
    private func navigateToDetail(for row: GeneralRow) {
        switch row {
        case .languageAndRegion:
            navigateToLanguageAndRegion()
        case .voice:
            navigateToVoiceSettings()
        case .beaconSettings:
            navigateToBeaconSettings()
        case .volumeSettings:
            navigateToVolumeSettings()
        case .manageDevices:
            navigateToManageDevices()
        case .siriShortcuts:
            navigateToSiriShortcuts()
        }
    }

    private func navigateToLanguageAndRegion() {
        // Push detailed Language and Region screen
        GDLogActionInfo("Opened 'Language and Region Settings'")
    }

    private func navigateToVoiceSettings() {
        // Push detailed Voice Settings screen
        GDLogActionInfo("Opened 'Voice Settings'")
    }

    private func navigateToBeaconSettings() {
        // Push detailed Beacon Settings screen
        GDLogActionInfo("Opened 'Beacon Settings'")
    }

    private func navigateToVolumeSettings() {
        // Push detailed Volume Settings screen
        GDLogActionInfo("Opened 'Volume Settings'")
    }

    private func navigateToManageDevices() {
        // Push detailed Manage Devices screen
        GDLogActionInfo("Opened 'Manage Devices'")
    }

    private func navigateToSiriShortcuts() {
        // Push detailed Siri Shortcuts screen
        GDLogActionInfo("Opened 'Siri Shortcuts'")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return GDLocalizedString("settings.section.general.description")
    }
}
