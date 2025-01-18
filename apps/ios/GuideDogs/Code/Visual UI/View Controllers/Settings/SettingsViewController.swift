//  SettingsViewController.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import UIKit
import AppCenterAnalytics

class SettingsViewController: BaseTableViewController {

    private enum Section: Int, CaseIterable {
        case general = 0
        case audio = 1
        case beacon = 2
        case callouts = 3
        case streetPreview = 4
        case troubleshooting = 5
        case about = 6
        case telemetry = 7
    }
    
    private enum CalloutsRow: Int, CaseIterable {
        case all = 0
        case poi = 1
        case mobility = 2
        case beacon = 3
        case shake = 4
    }
    
    private static let cellIdentifiers: [IndexPath: String] = [
        IndexPath(row: 0, section: Section.general.rawValue): "languageAndRegion",
        IndexPath(row: 1, section: Section.general.rawValue): "voice",
        IndexPath(row: 2, section: Section.general.rawValue): "volumeSettings",
        IndexPath(row: 3, section: Section.general.rawValue): "manageDevices",
        IndexPath(row: 4, section: Section.general.rawValue): "siriShortcuts",

        IndexPath(row: 0, section: Section.audio.rawValue): "mixAudio",

        IndexPath(row: 0, section: Section.beacon.rawValue): "beaconSettings",
  

        IndexPath(row: CalloutsRow.all.rawValue, section: Section.callouts.rawValue): "allCallouts",
        IndexPath(row: CalloutsRow.poi.rawValue, section: Section.callouts.rawValue): "poiCallouts",
        IndexPath(row: CalloutsRow.mobility.rawValue, section: Section.callouts.rawValue): "mobilityCallouts",
        IndexPath(row: CalloutsRow.beacon.rawValue, section: Section.callouts.rawValue): "beaconCallouts",
        IndexPath(row: CalloutsRow.shake.rawValue, section: Section.callouts.rawValue): "shakeCallouts",

        IndexPath(row: 0, section: Section.streetPreview.rawValue): "streetPreview",
        IndexPath(row: 0, section: Section.troubleshooting.rawValue): "troubleshooting",
        IndexPath(row: 0, section: Section.about.rawValue): "about",
        IndexPath(row: 0, section: Section.telemetry.rawValue): "telemetry"
    ]
    
    private static let collapsibleCalloutIndexPaths: [IndexPath] = [
        IndexPath(row: CalloutsRow.poi.rawValue, section: Section.callouts.rawValue),
        IndexPath(row: CalloutsRow.mobility.rawValue, section: Section.callouts.rawValue),
        IndexPath(row: CalloutsRow.beacon.rawValue, section: Section.callouts.rawValue),
        IndexPath(row: CalloutsRow.shake.rawValue, section: Section.callouts.rawValue)
    ]
    
    // MARK: Properties

    @IBOutlet weak var largeBannerContainerView: UIView!
    
    private var expandedSections: Set<Int> = []
    
    // Section Descriptions
    private static let sectionDescriptions: [Section: String] = [
        .general: "General settings for the app.",
        .audio: "Control how audio interacts with other media.",
        .beacon: "Settings for beacon management.",
        .callouts: "Manage the callouts that help navigate.",
        .streetPreview: "Settings for including unnamed roads.",
        .troubleshooting: "Options for troubleshooting the app.",
        .about: "Information about the app.",
        .telemetry: "Manage data collection and privacy."
    ]

    // MARK: View Life Cycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        GDLogActionInfo("Opened 'Settings'")

        GDATelemetry.trackScreenView("settings")

        self.title = GDLocalizedString("settings.screen_title")
        expandedSections = []
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }

       
        switch sectionType {
        case .general: return expandedSections.contains(section) ? 5 : 0
        case .audio: return expandedSections.contains(section) ? 1 : 0
        case .beacon: return expandedSections.contains(section) ? 1 : 0
        case .callouts:
            return SettingsContext.shared.automaticCalloutsEnabled && expandedSections.contains(section) ? 5 : 0
        case .streetPreview, .troubleshooting, .about, .telemetry:
            return expandedSections.contains(section) ? 1 : 0
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return expandedSections.contains(indexPath.section) ? UITableView.automaticDimension : 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard expandedSections.contains(indexPath.section) else {
            return UITableViewCell()
        }
        
        let identifier = SettingsViewController.cellIdentifiers[indexPath]
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier ?? "default", for: indexPath)
        
        switch Section(rawValue: indexPath.section) {
        case .callouts:
            configureCalloutCell(cell as! CalloutSettingsCellView, at: indexPath)
        case .telemetry:
            (cell as! TelemetrySettingsTableViewCell).parent = self
        case .audio:
            (cell as! MixAudioSettingCell).delegate = self
        default:
            break
        }
        
        return cell
    }
    
    private func configureCalloutCell(_ cell: CalloutSettingsCellView, at indexPath: IndexPath) {
        cell.delegate = self
        if let rowType = CalloutsRow(rawValue: indexPath.row) {
            switch rowType {
            case .all:
                cell.type = .all
            case .poi:
                cell.type = .poi
            case .mobility:
                cell.type = .mobility
            case .beacon:
                cell.type = .beacon
            case .shake:
                cell.type = .shake
            }
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }

        switch sectionType {
        case .general: return GDLocalizedString("settings.section.general")
        case .audio: return GDLocalizedString("settings.audio.media_controls")
        case .beacon: return GDLocalizedString("Beacon")
        case .callouts: return GDLocalizedString("menu.manage_callouts")
        case .about: return GDLocalizedString("settings.section.about")
        case .streetPreview: return GDLocalizedString("preview.title")
        case .troubleshooting: return GDLocalizedString("settings.section.troubleshooting")
        case .telemetry: return GDLocalizedString("settings.section.telemetry")
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }

        if expandedSections.contains(section) {
            return SettingsViewController.sectionDescriptions[sectionType]
        }

        switch sectionType {
        case .audio: return GDLocalizedString("settings.audio.mix_with_others.description")
        case .streetPreview: return GDLocalizedString("preview.include_unnamed_roads.subtitle")
        case .telemetry: return GDLocalizedString("settings.section.telemetry.footer")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }

        header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleHeaderTap(_:))))
        header.tag = section

        header.textLabel?.textColor = .white
        header.textLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        header.contentView.backgroundColor = UIColor(named: "HeaderBackgroundColor")

        // Accessibility
        header.accessibilityTraits = .header
        header.accessibilityLabel = SettingsViewController.sectionDescriptions[Section(rawValue: section)!]
        header.accessibilityHint = "Double tap to expand or collapse this section"

        let chevronImageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevronImageView.tintColor = .white
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        header.contentView.addSubview(chevronImageView)

        NSLayoutConstraint.activate([
            chevronImageView.trailingAnchor.constraint(equalTo: header.contentView.trailingAnchor, constant: -15),
            chevronImageView.centerYAnchor.constraint(equalTo: header.contentView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 20),
            chevronImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    @objc private func handleHeaderTap(_ gesture: UITapGestureRecognizer) {
            guard let header = gesture.view as? UITableViewHeaderFooterView else { return }
            let section = header.tag

            if section == Section.callouts.rawValue {
                // Navigate to CalloutsSettingsViewController
                let calloutsSettingsVC = CalloutSettingsViewController()
                self.navigationController?.pushViewController(calloutsSettingsVC, animated: true)
            } else {
                tableView.beginUpdates()
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                    tableView.reloadSections(IndexSet(integer: section), with: .automatic)
                    UIAccessibility.post(notification: .announcement, argument: "Section collapsed")
                } else {
                    expandedSections.insert(section)
                    tableView.reloadSections(IndexSet(integer: section), with: .automatic)
                    UIAccessibility.post(notification: .announcement, argument: "Section expanded")
                }
                tableView.endUpdates()
            }
    }

}

extension SettingsViewController: MixAudioSettingCellDelegate {
    func onSettingValueChanged(_ cell: MixAudioSettingCell, settingSwitch: UISwitch) {
        guard settingSwitch.isOn else {
            updateSetting(true)
            return
        }

        let alert = UIAlertController(title: GDLocalizedString("general.alert.confirmation_title"),
                                      message: GDLocalizedString("setting.audio.mix_with_others.confirmation"),
                                      preferredStyle: .alert)
        
        let mixAction = UIAlertAction(title: GDLocalizedString("settings.audio.mix_with_others.title"), style: .default) { [weak self] (_) in
            self?.updateSetting(false)
            self?.focusOnCell(cell)
        }
        alert.addAction(mixAction)
        alert.preferredAction = mixAction
        
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel, handler: { [weak self] (_) in
            settingSwitch.isOn = false
            GDATelemetry.track("settings.mix_audio.cancel", with: ["context": "app_settings"])
            self?.focusOnCell(cell)
        }))
        
        present(alert, animated: true)
    }

    private func updateSetting(_ newValue: Bool) {
        SettingsContext.shared.audioSessionMixesWithOthers = newValue
        AppContext.shared.audioEngine.mixWithOthers = newValue
        
        GDATelemetry.track("settings.mix_audio",
                           with: ["value": "\(SettingsContext.shared.audioSessionMixesWithOthers)",
                                  "context": "app_settings"])
    }
    
    private func focusOnCell(_ cell: MixAudioSettingCell) {
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .layoutChanged, argument: cell)
        }
    }
}

extension SettingsViewController: CalloutSettingsCellViewDelegate {
    func onCalloutSettingChanged(_ type: CalloutSettingCellType) {
        guard type == .all else {
            return
        }
        
        let indexPaths = SettingsViewController.collapsibleCalloutIndexPaths
        
        if SettingsContext.shared.automaticCalloutsEnabled && !tableView.contains(indexPaths: indexPaths) {
            tableView.insertRows(at: indexPaths, with: .automatic)
        } else if !SettingsContext.shared.automaticCalloutsEnabled && tableView.contains(indexPaths: indexPaths) {
            tableView.deleteRows(at: indexPaths, with: .automatic)
        }
    }
}

extension SettingsViewController: LargeBannerContainerView {
    
    func setLargeBannerHeight(_ height: CGFloat) {
        largeBannerContainerView.setHeight(height)
        tableView.reloadData()
    }
}
