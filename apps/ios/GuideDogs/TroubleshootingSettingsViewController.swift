import UIKit

class TroubleshootingViewController: UITableViewController {
    
    private enum TroubleshootingRow: Int, CaseIterable {
        case checkAudio = 0
        case clearMapData = 1
    }
    
    private static let cellIdentifiers: [TroubleshootingRow: String] = [
        .checkAudio: "checkAudio",
        .clearMapData: "clearMapData"
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = GDLocalizedString("settings.section.troubleshooting")
        
        // Register the specific cell identifiers
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "checkAudio")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "clearMapData")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return TroubleshootingRow.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let rowType = TroubleshootingRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }
        
        let identifier = TroubleshootingViewController.cellIdentifiers[rowType] ?? "default"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        cell.selectionStyle = .default
        
        switch rowType {
        case .checkAudio:
            cell.textLabel?.text = GDLocalizedString("troubleshooting.check_audio")
            cell.accessoryType = .disclosureIndicator
        case .clearMapData:
            cell.textLabel?.text = GDLocalizedString("settings.clear_data")
            cell.accessoryType = .disclosureIndicator
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let rowType = TroubleshootingRow(rawValue: indexPath.row) else {
            return
        }
        
        switch rowType {
        case .checkAudio:
            checkAudioStatus()
        case .clearMapData:
            clearMapDataConfirmation()
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Actions
    
    private func checkAudioStatus() {
        // Here, implement the functionality to check audio status.
        // This could involve presenting an alert or a new screen with audio information.
        let alert = UIAlertController(
            title: GDLocalizedString("troubleshooting.check_audio"),
            message: GDLocalizedString("troubleshooting.check_audio.explanation"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.ok"), style: .default))
        present(alert, animated: true)
    }
    
    private func clearMapDataConfirmation() {
        // Display a confirmation alert before clearing the map data
        let alert = UIAlertController(
            title: GDLocalizedString("settings.clear_cache.alert_title"),
            message: GDLocalizedString("settings.clear_cache.alert_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.confirm"), style: .destructive) { _ in
            self.clearMapData()
        })
        present(alert, animated: true)
    }
    
    private func clearMapData() {
        // Logic to clear stored map data goes here
        // For example, removing cached files or data from UserDefaults if relevant.
        // Notify the user after clearing data.
        let confirmationAlert = UIAlertController(
            title: GDLocalizedString("settings.clear_cache.alert_title"),
            message: GDLocalizedString("settings.clear_cache.no_service.message"),
            preferredStyle: .alert
        )
        confirmationAlert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.ok"), style: .default))
        present(confirmationAlert, animated: true)
    }
}

