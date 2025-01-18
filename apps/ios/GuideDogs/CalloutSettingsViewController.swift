import UIKit

class CalloutSettingsViewController: UITableViewController, CalloutSettingsCellViewDelegate {
    
    // MARK: - CalloutSettingsCellViewDelegate
    func onCalloutSettingChanged(_ type: CalloutSettingCellType) {
        // Handle callout setting changes here
        print("Callout setting changed for type: \(type)")
    }
    
    private enum CalloutsRow: Int, CaseIterable {
        case all = 0
        case poi = 1
        case mobility = 2
        case beacon = 3
        case shake = 4
    }
    
    private static let cellIdentifiers: [CalloutsRow: String] = [
        .all: "allCallouts",
        .poi: "poiCallouts",
        .mobility: "mobilityCallouts",
        .beacon: "beaconCallouts",
        .shake: "shakeCallouts"
    ]
    
    // Properties to store the states of each callout setting
    private var automaticCalloutsEnabled = SettingsContext.shared.automaticCalloutsEnabled
    private var poiCalloutsEnabled = true
    private var mobilityCalloutsEnabled = true
    private var beaconCalloutsEnabled = true
    private var shakeCalloutsEnabled = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = GDLocalizedString("menu.manage_callouts")
        
        // Register all cell identifiers
        for identifier in CalloutSettingsViewController.cellIdentifiers.values {
            self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: identifier)
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Only show additional rows when "Allow Callouts" is enabled
        return automaticCalloutsEnabled ? CalloutsRow.allCases.count : 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Determine the row type
        guard let rowType = CalloutsRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }
        
        // Get the identifier for the row type
        let identifier = CalloutSettingsViewController.cellIdentifiers[rowType] ?? "default"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        cell.selectionStyle = .none // Disable selection
        
        // Configure the toggle for each row
        let switchView = UISwitch(frame: .zero)
        switchView.addTarget(self, action: #selector(toggleCalloutSetting(_:)), for: .valueChanged)
        switchView.tag = rowType.rawValue
        cell.accessoryView = switchView
        
        // Configure the row content dynamically
        switch rowType {
        case .all:
            cell.textLabel?.text = GDLocalizedString("menu.manage_callouts.all")
            switchView.setOn(automaticCalloutsEnabled, animated: true)
        case .poi:
            cell.textLabel?.text = GDLocalizedString("menu.manage_callouts.poi")
            switchView.setOn(poiCalloutsEnabled, animated: true)
        case .mobility:
            cell.textLabel?.text = GDLocalizedString("menu.manage_callouts.mobility")
            switchView.setOn(mobilityCalloutsEnabled, animated: true)
        case .beacon:
            cell.textLabel?.text = GDLocalizedString("menu.manage_callouts.beacon")
            switchView.setOn(beaconCalloutsEnabled, animated: true)
        case .shake:
            cell.textLabel?.text = GDLocalizedString("menu.manage_callouts.shake")
            switchView.setOn(shakeCalloutsEnabled, animated: true)
        }
        
        return cell
    }
    
    // MARK: - Toggle Actions
    
    @objc private func toggleCalloutSetting(_ sender: UISwitch) {
        // Determine which toggle was changed based on its tag
        switch CalloutsRow(rawValue: sender.tag) {
        case .all:
            automaticCalloutsEnabled = sender.isOn
            SettingsContext.shared.automaticCalloutsEnabled = sender.isOn
            logCalloutToggle(for: "all", state: sender.isOn)
            tableView.reloadData() // Refresh table to show/hide rows
        case .poi:
            poiCalloutsEnabled = sender.isOn
            logCalloutToggle(for: "poi", state: sender.isOn)
        case .mobility:
            mobilityCalloutsEnabled = sender.isOn
            logCalloutToggle(for: "mobility", state: sender.isOn)
        case .beacon:
            beaconCalloutsEnabled = sender.isOn
            logCalloutToggle(for: "beacon", state: sender.isOn)
        case .shake:
            shakeCalloutsEnabled = sender.isOn
            logCalloutToggle(for: "shake", state: sender.isOn)
        case .none:
            break
        }
    }
    
    // MARK: - Logging Function
    
    private func logCalloutToggle(for type: String, state: Bool) {
        let logMessage = "Toggled \(type) callouts to: \(state)"
        GDLogActionInfo(logMessage) // Use GDLog for logging
        GDATelemetry.track("callout_toggle", with: ["type": type, "state": "\(state)"])
    }
}

