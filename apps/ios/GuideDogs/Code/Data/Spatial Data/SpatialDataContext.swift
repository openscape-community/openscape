//
//  SpatialDataContext.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import RealmSwift
import CoreLocation

enum SpatialDataState {
    case error
    case loadingCategories
    case waitingForLocation
    case loading
    case ready
}

enum SpatialDataContextError: Error {
    case missingData
}

extension Notification.Name {
    static let spatialDataStateChanged = Notification.Name("GDASpatialDataStateChanged")
    static let tilesDidUpdate = Notification.Name("TilesDidUpdate")
    static let locationUpdated = Notification.Name("GDALocationUpdated")
}

// MARK: -

class SpatialDataContext: NSObject, SpatialDataProtocol {
    
    // MARK: Constants
    
    struct Keys {
        static let state = "GDAGeolocationState"
        static let location = "GDAGeolocation"
        static let categoriesVersion = "GDACategoriesVersion"
    }
    
    // MARK: - Properties
    
    static let zoomLevel: UInt = 16
    static let cacheDistance: CLLocationDistance = 1000
    static let initialPOISearchDistance: CLLocationDistance = 200
    static let expansionPOISearchDistance: CLLocationDistance = 200
    static let refreshTimeInterval: TimeInterval = 5.0
    static let refreshDistanceInterval: CLLocationDistance = 5.0

    private(set) weak var geolocationManager: GeolocationManagerProtocol?
    private(set) var motionActivityContext: MotionActivityProtocol

    private weak var deviceContext: UIDeviceManager!
    private let serviceModel: OSMServiceModelProtocol
    
    let destinationManager: DestinationManagerProtocol
    
    private weak var settings: SettingsContext?

    fileprivate var updateFilter: MotionActivityUpdateFilter
    fileprivate var superCategories: SuperCategories
    
    fileprivate var currentLocation: CLLocation?
    fileprivate var originalRequestLocation: CLLocation?

    fileprivate var prioritize = false
    private var expectedTilesCount = 0
    private var canceledTilesCount = 0
    private var toFetch: [VectorTile] = []
    
    // MARK: Synchronized Properties
    
    private let networkQueue = DispatchQueue(label: "services.soundscape.spatialdata.network", qos: .utility)
    private var dispatchQueue = DispatchQueue(label: "services.soundscape.spatialdata", qos: .utility, attributes: .concurrent)
    private var fetchingTiles = false
    
    /// Set of tiles the spatial data context is currently using to generate the list of spatial data result entities around the user
    private var tiles: Set<VectorTile> = []
    
    // MARK: Error Recovery Properties
    
    private let errorRecoveryDelay = 60.0
    private var errorRecoveryTask: DispatchWorkItem?
    
    // MARK: Observed Properties
    
    private(set) var state = SpatialDataState.loadingCategories {
        didSet {
            guard oldValue != state else {
                return
            }
            
            if state == .error {
                scheduleErrorRecovery()
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name.spatialDataStateChanged, object: self, userInfo: [SpatialDataContext.Keys.state: self.state])
            }
        }
    }
    
    // MARK: Computed Properties
    
    private var currentTile: VectorTile? {
        guard let location = currentLocation else {
            return nil
        }
        
        return VectorTile.tileForLocation(location, zoom: SpatialDataContext.zoomLevel)
    }
    
    var loadedSpatialData: Bool {
        var loadedSpatialData = false
        
        dispatchQueue.sync {
            loadedSpatialData = !fetchingTiles && tiles.count > 0
        }
        
        return loadedSpatialData
    }
    
    var currentTiles: [VectorTile] {
        var currentTiles: [VectorTile] = []
        
        dispatchQueue.sync {
            for tile in tiles {
                currentTiles.append(tile)
            }
        }
        
        return currentTiles
    }
    
    // MARK: - Initialization

    init(geolocation: GeolocationManagerProtocol,
         motionActivity: MotionActivityProtocol,
         services: OSMServiceModelProtocol,
         device: UIDeviceManager,
         destinationManager destinations: DestinationManagerProtocol,
         settings settingsContext: SettingsContext) {
        
        deviceContext = device
        geolocationManager = geolocation
        motionActivityContext = motionActivity

        serviceModel = services
        destinationManager = destinations
        settings = settingsContext
        
        updateFilter = MotionActivityUpdateFilter(minTime: SpatialDataContext.refreshTimeInterval,
                                                  minDistance: SpatialDataContext.refreshDistanceInterval,
                                                  motionActivity: motionActivity)
        
        // Parse the super categories from the assets file
        guard let categories = SpatialDataContext.loadDefaultCategories() else {
            GDLogAppError("Unable to load super categories")
            state = .error
            superCategories = [:]
            super.init()
            return
        }
        
        state = .waitingForLocation
        superCategories = categories
        
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.onNetworkConnectionDidChange), name: Notification.Name.networkConnectionChanged, object: nil)
        
        // Register to receive a notification when the app has finished initializing
        NotificationCenter.default.addObserver(self, selector: #selector(self.onAppDidInitialize), name: NSNotification.Name.appDidInitialize, object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCloudKeyValueStoreDidChange),
                                               name: .cloudKeyValueStoreDidChange,
                                               object: nil)
    }
    
    @objc private func onAppDidInitialize() {
        // Run the initial spatial data update
        
        guard let location = AppContext.shared.geolocationManager.location else {
            GDLogSpatialDataWarn("SpatialDataContext initialized, but no location data is available yet...")
            return
        }
        
        currentLocation = location
        
        guard updateFilter.shouldUpdate(location: location) else {
            GDLogSpatialDataWarn("SpatialDataContext initialized, but should update returned false...")
            return
        }
        
        state = .loading
        
        // There is no point to try updating if we don't have a network connection
        guard deviceContext.isNetworkConnectionAvailable else {
            let tile = VectorTile.tileForLocation(location, zoom: SpatialDataContext.zoomLevel)
            
            // This is only an error if the current tile isn't cached
            if SpatialDataCache.isCached(tile: tile) {
                state = .ready
            } else {
                state = .error
            }
            
            return
        }
        
        updateSpatialDataAsync(location: location)
    }
    
    func start() {
        geolocationManager?.updateDelegate = self
        
        motionActivityContext.startActivityUpdates()
        
        if !FirstUseExperience.didComplete(.iCloudBackup) {
            // Getting the `.initialSync` notification from iCloud is not reliable so we force sync
            GDLogCloudInfo("Performing initial cloud sync")
            AppContext.shared.cloudKeyValueStore.syncReferenceEntities(reason: .initialSync) {
                AppContext.shared.cloudKeyValueStore.syncRoutes(reason: .initialSync)
                FirstUseExperience.setDidComplete(for: .iCloudBackup)
            }
        }
    }
    
    func stop() {
        geolocationManager?.updateDelegate = nil
        
        motionActivityContext.stopActivityUpdates()
    }
    
    // MARK: - Instance Methods
    
    func clearCache() -> Bool {
        let manager = FileManager.default
        let config = RealmHelper.cacheConfig
        
        guard let fileURL = config.fileURL else {
            return false
        }
        
        // Recreate the cached data in a new
        // Realm file
        RealmHelper.incrementCacheConfig()
        
        let realmFiles = [fileURL,
                          fileURL.appendingPathExtension("lock"),
                          fileURL.appendingPathExtension("management"),
                          fileURL.appendingPathExtension("note")]
        
        var failed = false
        
        for url in realmFiles {
            do {
                try manager.removeItem(at: url)
            } catch {
                GDLogSpatialDataError("Unable to delete \(url), error: \(error.localizedDescription)")
                failed = true
            }
        }
        
        if !failed {
            GDLogSpatialDataVerbose("Cache deleted!")
        }
        
        dispatchQueue.sync(flags: .barrier) {
            tiles.removeAll()
        }
        
        AppContext.shared.calloutHistory.clear()
        
        if let loc = geolocationManager?.location {
            updateSpatialDataAsync(location: loc, reloadPORs: true)
        }
        
        return !failed
    }
    
    func getDataView(for location: CLLocation, searchDistance: CLLocationDistance = SpatialDataContext.initialPOISearchDistance) -> SpatialDataViewProtocol? {
        var results: SpatialDataView?
        
        dispatchQueue.sync {
            let tile = VectorTile.tileForLocation(location, zoom: SpatialDataContext.zoomLevel)
            
            // Ensure we at least have the current tile and the user's current location
            guard SpatialDataCache.isCached(tile: tile) else {
                return
            }
            
            // TODO: If tiles to load haven't changed, and we are still on the same thread, return the previous view
            
            results = SpatialDataView(location: location,
                                      range: searchDistance,
                                      zoom: SpatialDataContext.zoomLevel,
                                      geolocation: geolocationManager,
                                      motionActivity: motionActivityContext,
                                      destinationManager: destinationManager)
        }
        
        return results
    }
    
    func getCurrentDataView(searchDistance: CLLocationDistance = SpatialDataContext.initialPOISearchDistance) -> SpatialDataViewProtocol? {
        guard let location = currentLocation else {
            return nil
        }
        
        return getDataView(for: location, searchDistance: searchDistance)
    }
    
    func getCurrentDataView(initialSearchDistance: CLLocationDistance = SpatialDataContext.initialPOISearchDistance, shouldExpandDataView: (SpatialDataViewProtocol) -> Bool) -> SpatialDataViewProtocol? {
        // Fetch cached data
        var expansions = 0
        var range = initialSearchDistance
        var dataView = AppContext.shared.spatialDataContext.getCurrentDataView(searchDistance: range)
        
        // Load Nearby
        //
        // Progressively expand search distance until 50 results are returned of
        // seach distance reaches `cacheDistance`.
        while range <= SpatialDataContext.cacheDistance {
            defer {
                range += SpatialDataContext.expansionPOISearchDistance
            }
            
            // Get the spatial data view and filter POIs into quadrants
            dataView = AppContext.shared.spatialDataContext.getCurrentDataView(searchDistance: range)
            
            guard let dataView = dataView else {
                return nil
            }
            
            if shouldExpandDataView(dataView) {
                expansions += 1
                continue
            }
            
            break
        }
        
        return dataView
    }
    
    enum ServiceConnectionState {
        /// Couldn't find the current tile to request
        case currentTileNil
        /// Called the service and received a bad response or error
        case failed
        /// Success.
        case success
    }
    func checkServiceConnection() async -> ServiceConnectionState {
        guard let tile = currentTile else {
            return .currentTileNil
        }
        do {
            _ = try await serviceModel.getTileData(tile: tile, categories: [:])
            return .success
        } catch {
            return .failed
        }
    }
    
    func checkServiceConnection(completionHandler: @escaping (_ success: Bool) -> Void) {
        guard let _ = currentTile else {
            completionHandler(false)
            return
        }
        Task {
            let status = await checkServiceConnection()
            completionHandler(status == .success)
        }
    }
    
    private func scheduleErrorRecovery() {
        GDATelemetry.track("services.error.scheduling_retry")
        
        errorRecoveryTask = DispatchWorkItem { [weak self] in
            guard let `self` = self else { return }
            
            guard let location = self.currentLocation, self.deviceContext.isNetworkConnectionAvailable else {
                self.scheduleErrorRecovery()
                return
            }
            
            GDLogAppVerbose("RECOVERY: Running network error recovery. Attempting to download data.")
            
            self.updateSpatialDataAsync(location: location)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + errorRecoveryDelay, execute: errorRecoveryTask!)
    }
    
    func updateSpatialData(at location: CLLocation, completion: @escaping () -> Void) -> Progress? {
        guard let (task, progress) = updateSpatialDataAsync(location: location, overridePrioritizeCurrent: false) else {
            // If data for the given location is already cached,
            // return immediately
            completion()
            return nil
        }
        
        Task {
            _ = await task.result
            completion()
        }
        return progress
    }
    
    /// Since the progress isn't returned until after completion, it isn't very useful.
    func updateSpatialData(at location: CLLocation) async -> Progress? {
        guard let (task, progress) = updateSpatialDataAsync(location: location, overridePrioritizeCurrent: false) else {
            return nil
        }
        _ = await task.value
        return progress
    }
    
    @discardableResult
    fileprivate func updateSpatialDataAsync(location: CLLocation, reloadPORs: Bool = false, overridePrioritizeCurrent: Bool? = nil) -> (Task<(), Never>, Progress)? {
        let current = VectorTile.tileForLocation(location, zoom: SpatialDataContext.zoomLevel)
        let currentCached = SpatialDataCache.isCached(tile: current)
        
        if let overridePrioritizeCurrent = overridePrioritizeCurrent {
            prioritize = overridePrioritizeCurrent
        } else {
            // Only prioritize the current tile if we don't have it cached and we aren't currently clearing and rebuilding the cache
            prioritize = !currentCached && !reloadPORs
        }
        
        let checked = dispatchQueue.sync(flags: .barrier) { () -> Bool in
            guard !self.fetchingTiles else {
                return false
            }
            
            // Update the time/location filter
            self.updateFilter.update(location: location)
            
            // Figure out which tiles we need to fetch
            (self.tiles, self.toFetch) = SpatialDataContext.checkForTiles(location: location,
                                                                          tiles: self.tiles,
                                                                          includePORs: reloadPORs,
                                                                          prioritizeCurrent: prioritize)
            
            // Update tile fetching state
            self.fetchingTiles = true
            self.canceledTilesCount = 0
            self.expectedTilesCount = self.tiles.count + self.toFetch.count
            self.originalRequestLocation = location
            
            return true
        }
        
        // Only allow one update to occur at a time
        guard checked else {
            // If the current tile is already cached, pass on the location update immediately
            if currentCached {
                notifyLocationUpdated(location)
            }
            
            // There are no tiles to fetch
            return nil
        }
        
        // Make sure there are tiles we need to cache
        guard toFetch.count > 0 else {
            GDLogSpatialDataVerbose("No new tiles to fetch")
            
            dispatchQueue.sync(flags: .barrier) {
                fetchingTiles = false
            }
            
            state = .ready
            notifyLocationUpdated(location)
            
            // There are no tiles to fetch
            return nil
        }
        
        // We are fetching tiles, but if we already have the current tile, pass on the location update immediately
        if !toFetch.contains(current) {
            notifyLocationUpdated(location)
        }
        
        // We actually have some tiles to fetch
        GDLogSpatialDataVerbose("Fetching \(self.toFetch.count) tiles.")
        
        state = .loading
        
        let progress = Progress(totalUnitCount: Int64(toFetch.count))
        let task = Task {
            return await withTaskGroup(of: Void.self, body: { group in
                for tile in toFetch {
                    group.addTask {
                        if !SpatialDataCache.needsFetching(tile: tile) {
                            self.processFetchedTile(tile, progress: progress)
                        } else {
                            do {
                                try await self.fetchTileAsync(tile, progress: progress)
                            } catch {
                                GDLogSpatialDataError("Unable to fetch tile \(tile.quadKey). Cancelling")
                                
                                self.canceledTilesCount += 1
                                
                                if tile == self.currentTile {
                                    // The user is in an unsupported region, or has no internet, or Azure is down...
                                    self.state = .error
                                }
                            }
                        }
                    }
                }
            })
        }
        
        return (task, progress)
    }
    
    /// Makes three attempts to fetch the specified tile. If unsuccessful, it will throw the last error thrown by the OSM service model.
    /// If successful, it will appropriately update local tile information
    private func fetchTileAsync(_ tile: VectorTile, progress: Progress) async throws {
        let serviceResult = try await self.serviceModel.getTileData(tile: tile, categories: superCategories, tries: 3)
        
        switch serviceResult {
        case .notModified:
            await SpatialDataCache.extendTileExpiration(tile)
            self.processFetchedTile(tile, progress: progress)
        case .modified(_, let tileData):
            await SpatialDataCache.storeTile(tile, data: tileData)
            self.processFetchedTile(tile, progress: progress)
        }
    }
    
    private func processFetchedTile(_ tile: VectorTile, progress: Progress) {
        let loc = currentLocation ?? originalRequestLocation
        
        /// We got the tile
        dispatchQueue.sync(flags: .barrier) {
            _ = self.tiles.insert(tile)
        }
        
        // If the tile we just fetched is the current tile (the tile the user is
        // currently in), immediately pass on the location update...
        if tile == currentTile, let location = loc {
            notifyLocationUpdated(location, tilesChanged: true)
        }
        
        var tilesCount = 0
        dispatchQueue.sync(flags: .barrier) {
            tilesCount = self.tiles.count
        }
        
        // If we have fetched all of the tiles (minus the ones we had to cancel), then we are ready to finish up
        if expectedTilesCount == tilesCount + canceledTilesCount {
            dispatchQueue.sync(flags: .barrier) {
                fetchingTiles = false
            }
            
            GDLogSpatialDataVerbose("Requested \(toFetch.count) tiles; Canceled \(canceledTilesCount); \(tilesCount) tiles ready.")
            
            if prioritize, let location = loc {
                updateSpatialDataAsync(location: location)
            }
            
            if state != .error {
                state = .ready
            }
            
            if let location = loc {
                notifyLocationUpdated(location, tilesChanged: true)
            }
        }
        
        progress.completedUnitCount += 1
    }
    
    fileprivate func notifyLocationUpdated(_ location: CLLocation, tilesChanged: Bool = false) {
        DispatchQueue.main.async {
            AppContext.process(LocationUpdatedEvent(location))
            
            NotificationCenter.default.post(name: Notification.Name.locationUpdated,
                                            object: self,
                                            userInfo: [SpatialDataContext.Keys.location: location])
            
            if tilesChanged {
                NotificationCenter.default.post(name: Notification.Name.tilesDidUpdate, object: self, userInfo: nil)
            }
        }
    }
    
    @objc private func onNetworkConnectionDidChange(_ notification: NSNotification) {
        guard AppContext.shared.state == .normal else {
            return
        }
        
        guard let isNetworkConnectionAvailable = notification.userInfo?[UIDeviceManager.Keys.isNetworkAvailable] as? Bool else {
            return
        }
        
        if isNetworkConnectionAvailable == true {
            // When the type of internet connection changes (WiFi or Cellular), kick off
            // a new spatial data update. This should help solve edge cases when the user
            // purposefully turns off wifi when having wifi network authentication issues
            guard let location = currentLocation else {
                return
            }
            
            errorRecoveryTask?.cancel()
            
            updateSpatialDataAsync(location: location)
        }
    }
    
    // MARK: - Class Methods
    
    /// Given the user's location and the current set of tiles we have loaded and are tracking, this
    /// method returns the remaining set of tiles we should continue to track, and the list of new
    /// tiles we need to download.
    ///
    /// - Parameters:
    ///   - location: User's current location
    ///   - tiles: The set of tiles currently downloaded around the user
    /// - Returns: The set of tiles currently downloaded that should still be tracked, and a list of new tiles to download and track.
    public class func checkForTiles(location: CLLocation, tiles: Set<VectorTile>, includePORs: Bool, prioritizeCurrent: Bool = false) -> (Set<VectorTile>, [VectorTile]) {
        guard !prioritizeCurrent else {
            var needed = [VectorTile.tileForLocation(location, zoom: SpatialDataContext.zoomLevel)]
            
            if includePORs {
                needed = Array(SpatialDataCache.tiles(forDestinations: true, forReferences: true, at: zoomLevel).union(needed))
            }
            
            return (Set<VectorTile>(), needed)
        }
        
        var neededTiles = VectorTile.tilesForRegion(location, radius: SpatialDataContext.cacheDistance, zoom: SpatialDataContext.zoomLevel)
        
        if includePORs {
            neededTiles = Array(SpatialDataCache.tiles(forDestinations: true, forReferences: true, at: zoomLevel).union(neededTiles))
        }
        
        let remainingTiles = Set(tiles.filter { neededTiles.contains($0) }) // Remove tile we don't need anymore
        let missingTiles = neededTiles.filter { !remainingTiles.contains($0) } // Get the tiles we need but don't have
        
        return (remainingTiles, missingTiles)
    }
    
    private class func loadDefaultCategories() -> SuperCategories? {
        GDLogAppInfo("Loading default super categories")
        
        guard let path = Bundle.main.path(forResource: "categories", ofType: "json") else {
            GDLogAppError("Soundscape must have categories! Couldn't load default categories")
            return nil
        }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            GDLogAppError("Soundscape must have categories! Couldn't load default categories")
            return nil
        }
        
        guard let (version, categories) = SuperCategory.parseCategories(from: data) else {
            GDLogAppError("Soundscape must have categories! Couldn't parse default categories")
            return nil
        }
        
        guard categories.count > 0 else {
            GDLogAppError("Soundscape must have categories! There must be 1 or more default categories")
            return nil
        }
        
        // Get the current version of the categories file
        let currentVersion = UserDefaults.standard.integer(forKey: Keys.categoriesVersion)
        
        guard currentVersion != 0 else {
            // This is the first time the file has been read. Save the version number.
            UserDefaults.standard.set(version, forKey: Keys.categoriesVersion)
            return categories
        }
        
        // Check if the version has changed
        if currentVersion != version {
            // The version has changed, expire tiles to make sure they reload with appropriately assigned super categories
            UserDefaults.standard.set(version, forKey: Keys.categoriesVersion)
            Task {
                await SpatialDataCache.expireAllTiles()
            }
        }
        
        return categories
    }
        
}

extension SpatialDataContext: GeolocationManagerUpdateDelegate {
    
    func didUpdateLocation(_ location: CLLocation) {
        currentLocation = location
        
        AppContext.shared.audioEngine.updateUserLocation(location)
        
        if state == .waitingForLocation {
            // We have a location now so we shouldn't be waiting in this state any more
            state = .ready
        }
        
        guard deviceContext.isNetworkConnectionAvailable && updateFilter.shouldUpdate(location: location) else {
            // This case is very common, so we don't output a log statement here...
            notifyLocationUpdated(location)
            return
        }
        
        updateSpatialDataAsync(location: location)
    }
    
}

extension SpatialDataContext {
    
    @objc private func handleCloudKeyValueStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let changeReason = userInfo[CloudKeyValueStore.NotificationKeys.reason] as? CloudKeyValueStoreChangeReason,
            let changedKeys = userInfo[CloudKeyValueStore.NotificationKeys.changedKeys] as? [String],
            let cloudStore = notification.object as? CloudKeyValueStore else {
                GDLogAppError("Unable to handle cloud key-value store did changed notification")
                return
        }
        
        switch changeReason {
        case .initialSync, .serverChanged:
            // Sync only changed keys
            cloudStore.syncReferenceEntities(reason: changeReason, changedKeys: changedKeys) {
                cloudStore.syncRoutes(reason: changeReason, changedKeys: changedKeys)
            }
        case .accountChanged:
            // Sync all entities
            cloudStore.syncReferenceEntities(reason: changeReason) {
                cloudStore.syncRoutes(reason: changeReason)
            }
        case .quotaViolationChange:
            showQuotaViolationAlert()
        }
    }
    
    private func showQuotaViolationAlert() {
        guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else { return }
        
        let alertController = UIAlertController(title: GDLocalizedString("icloud.kv_store.quota_violation_alert.title"),
                                                message: GDLocalizedString("icloud.kv_store.quota_violation_alert.message"),
                                                preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: GDLocalizationUnnecessary("Dismiss"), style: .cancel, handler: nil))
        
        DispatchQueue.main.async {
            rootViewController.present(alertController, animated: true, completion: nil)
        }
    }
    
}
