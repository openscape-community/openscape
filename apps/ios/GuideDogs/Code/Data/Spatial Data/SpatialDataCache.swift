//
//  SpatialDataCache.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import RealmSwift
import MapKit

extension SpatialDataCache {
    
    struct Predicates {
        static let lastSelectedDate = NSPredicate(format: "lastSelectedDate != NULL")
        
        static func distance(_ coordinate: CLLocationCoordinate2D,
                             span: CLLocationDistance? = nil,
                             latKey: String = "centroidLatitude",
                             lonKey: String = "centroidLongitude") -> NSPredicate {
            let range = span ?? SpatialDataContext.cacheDistance * 2
            
            return NSPredicate(centerCoordinate: coordinate,
                               span: range, /* `span` is the diameter */
                               latitudeKey: latKey,
                               longitudeKey: lonKey)
        }
    }
}

/// Note that the SpatialDataCache is entirely static.
/// Manages the ``RealmHelper.cache`` realm
@globalActor actor SpatialDataCache {
    static let shared = SpatialDataCache()
    // MARK: Geocoders
    
    private static var geocoder: Geocoder?
    
    static func useDefaultGeocoder() {
        self.geocoder = Geocoder(geocoder: CLGeocoder())
    }
    
    static func register(geocoder: AddressGeocoderProtocol) {
        self.geocoder = Geocoder(geocoder: geocoder)
    }
    
    // MARK: Search Providers
    
    private static var poiSearchProviders: [POISearchProviderProtocol] = []
    private static let osmPoiSearchProvider = OSMPOISearchProvider()
    
    static func useDefaultSearchProviders() {
        register(provider: osmPoiSearchProvider)
        register(provider: AddressSearchProvider())
        register(provider: GenericLocationSearchProvider())
    }
    
    static func register(provider: POISearchProviderProtocol) {
        guard !poiSearchProviders.contains(where: { $0.providerName == provider.providerName }) else {
            return
        }
        
        poiSearchProviders.append(provider)
    }
    
    static func removeAllProviders() {
        poiSearchProviders = []
    }
 
    // MARK: Realm Search
    
    fileprivate static func objectsFromAllProviders(predicate: NSPredicate) -> [POI] {
        var pois: [POI] = []
        
        for provider in poiSearchProviders {
            let providerPOIs = provider.objects(predicate: predicate)
            pois.append(contentsOf: providerPOIs)
        }
        
        return pois
    }
    
    static func genericLocationsNear(_ location: CLLocation, range: CLLocationDistance? = nil) -> [POI] {
        guard let index = poiSearchProviders.firstIndex(where: { $0.providerName == "GenericLocationSearchProvider" }) else {
            return []
        }
        
        let predicate = Predicates.distance(location.coordinate,
                                            span: range != nil ? range! * 2 : nil,
                                            latKey: "latitude",
                                            lonKey: "longitude")
        
        return poiSearchProviders[index].objects(predicate: predicate)
    }
    
    /// Search all caches for a POI with the given key. Keys should be unique
    /// across all POI types, so this will return the first POI any POISearchProviderProtocol
    /// object finds
    ///
    /// - Parameter key: The key to search for
    /// - Returns: Optionally a POI instance if one is found
    static func searchByKey(key: String) -> POI? {
        // In release builds, the default search provider (`POISearchProvider()`) is set in
        // `AppDelegate.applicationDidFinishLaunchingWithOptions`. In unit tests, you should
        // set the search provider in the `setUp` method of your unit test class (and call
        // `SpatialDataSearch.removeAllProviders()` in the `tearDown` method).
        assert(!poiSearchProviders.isEmpty, "A search provider must be specified for SpatialDataSearch")
        
        for provider in poiSearchProviders {
            if let poi = provider.search(byKey: key) {
                return poi
            }
        }
        
        return nil
    }
    
    // MARK: Road Entities

    static func road(withKey key: String) -> Road? {
        return osmPoiSearchProvider.search(byKey: key) as? Road
    }
    
    static func roads(withPredicate predicate: NSPredicate) -> [Road]? {
        return osmPoiSearchProvider.objects(predicate: predicate) as? [Road]
    }
    
    // MARK: Intersection Entities
    
    static func intersectionEntities(with predicate: NSPredicate) -> [Intersection] {
        return autoreleasepool {
            guard let database = try? RealmHelper.getCacheRealm() else {
                return []
            }
            
            return Array(database.objects(Intersection.self).filter(predicate))
        }
    }
    
    static func intersectionByKey(_ key: String) -> Intersection? {
        return autoreleasepool {
            guard let database = try? RealmHelper.getCacheRealm() else {
                return nil
            }
            
            return database.object(ofType: Intersection.self, forPrimaryKey: key)
        }
    }
    
    /// Returns all the intersections that connect to a given road
    static func intersections(forRoadKey roadKey: String) -> [Intersection]? {
        return intersections(forRoadKey: roadKey, inRegion: nil)
    }
    
    /// Returns all the intersections that connect to a given road
    static func intersection(forRoadKey roadKey: String, atCoordinate coordinate: CLLocationCoordinate2D) -> Intersection? {
        return intersections(forRoadKey: roadKey)?.first(where: { $0.coordinate == coordinate })
    }
    
    /// Returns all the intersections that connect to a given road, within a region.
    static func intersections(forRoadKey roadKey: String, inRegion region: MKCoordinateRegion?) -> [Intersection]? {
        let roadsPredicate = NSPredicate(format: "ANY roadIds.id == '\(roadKey)'")
        
        let predicate: NSPredicate
        
        if let region = region {
            let regionPredicate = NSPredicate(region: region)
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [regionPredicate, roadsPredicate])
        } else {
            predicate = roadsPredicate
        }
        
        return intersectionEntities(with: predicate)
    }
    
    // MARK: VectorTile Tools
    
    static func tiles(forDestinations: Bool, forReferences: Bool, at zoomLevel: UInt) -> Set<VectorTile> {
        var tiles: Set<VectorTile> = []
        
        if forReferences {
            let porTiles = SpatialDataCustom.tilesForReferenceEntities(at: zoomLevel)
            for porTile in porTiles {
                tiles.insert(porTile)
            }
        }
        
        let manager = AppContext.shared.spatialDataContext.destinationManager
        if forDestinations, let destination = manager.destination {
            tiles.insert(VectorTile(latitude: destination.latitude, longitude: destination.longitude, zoom: zoomLevel))
        }
        
        return tiles
    }
    
    static func tileData(for tiles: [VectorTile]) -> [TileData] {
        do {
            let cache = try RealmHelper.getCacheRealm()
            return Array(cache.objects(TileData.self).filter(NSPredicate(format: "quadkey IN %@", tiles.map({ $0.quadKey }))))
        } catch {
            return []
        }
    }
    
    // MARK: POI Type
    
    static func isAddress(poi: POI) -> Bool {
        return poi as? Address != nil
    }
    
    // MARK: Search by POI Characteristic
    
    private static func lastSelectedObjects() -> [POI] {
        let predicate: NSPredicate = Predicates.lastSelectedDate
        
        return objectsFromAllProviders(predicate: predicate)
    }
    
    static func recentlySelectedObjects() -> [POI] {
        let sortPredicate = Sort.lastSelected()
        return SpatialDataCache.lastSelectedObjects().sorted(by: sortPredicate, maxLength: 5)
    }
    
    static func fetchEstimatedCoordinate(address: String, in region: CLRegion? = nil, completionHandler: @escaping (GeocodedAddress?) -> Void) {
        guard let geocoder = geocoder else {
            GDLogSpatialDataError("Geocode Coordinate Error - Geocoder has not been initialized")
            
            completionHandler(nil)
            return
        }
        
        geocoder.geocodeAddressString(address: address, in: region) { (results) in
            guard let results = results  else {
                GDLogSpatialDataError("Geocode Coordinate Error - No results returned")
                
                GDATelemetry.track("geocode.coordinates.error.no_results")
                
                completionHandler(nil)
                return
            }
            
            completionHandler(results.first)
        }
    }
    
    static func fetchEstimatedAddress(location: CLLocation, completionHandler: @escaping (GeocodedAddress?) -> Void) {
        guard let geocoder = geocoder else {
            GDLogSpatialDataError("Geocode Address Error - Geocoder has not been initialized")
            
            completionHandler(nil)
            return
        }
        
        geocoder.geocodeLocation(location: location) { (results) in
            guard let results = results  else {
                GDLogSpatialDataError("Geocode Address Error - No results returned")
                
                completionHandler(nil)
                return
            }
            
            completionHandler(results.first)
        }
    }
    
    // MARK: Update Cache
    
    /// Checks if the tile is in the cache
    /// - Parameter tile: The VectorTile to check for
    static func isCached(tile: VectorTile) -> Bool {
        do {
            return try autoreleasepool {
                let cache = try RealmHelper.getCacheRealm()
                
                guard cache.object(ofType: TileData.self, forPrimaryKey: tile.quadKey) != nil else {
                    // The tile isn't in the cache
                    GDLogSpatialDataVerbose("Tile Miss: (\(tile.x), \(tile.y), \(tile.zoom))")
                    return false
                }
                
                // The tile is cached and still has time to live, so return the cached version
                GDLogSpatialDataVerbose("Tile Hit: (\(tile.x), \(tile.y), \(tile.zoom))")
                return true
            }
        } catch {
            GDLogSpatialDataError("Failed `isCached(tile)` with error: \(error)")
            return false
        }
    }
    
    /// Checks if the tile needs to be fetched (it either isn't in the cache or it has expired)
    /// - Parameter tile: VectorTile to check for
    static func needsFetching(tile: VectorTile) -> Bool {
        do {
            return try autoreleasepool {
                let cache = try RealmHelper.getCacheRealm()
                
                guard let cachedTile = cache.object(ofType: TileData.self, forPrimaryKey: tile.quadKey) else {
                    // The tile isn't in the cache
                    GDLogSpatialDataVerbose("Tile Miss: (\(tile.x), \(tile.y), \(tile.zoom))")
                    return true
                }
                
                guard cachedTile.ttl as Date > Date() else {
                    // The tile is in the cache, but the cache has expired
                    GDLogSpatialDataVerbose("Tile Expired: (\(tile.x), \(tile.y), \(tile.zoom))")
                    return true
                }
                
                // The tile is cached and still has time to live, so it doesn't need fetched
                GDLogSpatialDataVerbose("Tile Hit: (\(tile.x), \(tile.y), \(tile.zoom))")
                return false
            }
        } catch {
            GDLogSpatialDataError("Failed `needsFetching(tile:`")
            return false
        }
    }
    
    @SpatialDataCache
    static func storeTile(_ tile: VectorTile, data: TileData) async {
        do {
            try await Task { // task is effectively async autoreleasepool
                let cache = try await RealmHelper.getCacheRealm(actor: SpatialDataCache.shared)
                
                // Remove the existing tiles before storing the updated tile so that we remove old (bad)
                // intersection data from before we fixed the server intersection code (where multiple versions
                // of the same intersection were being returned in adjacent tiles)
                // NOTE: it looks like this is migration-related code?
                if let existingTile = cache.object(ofType: TileData.self, forPrimaryKey: tile.quadKey) {
                    try await cache.asyncWrite {
                        cache.delete(existingTile.intersections)
                    }
                }
                
                try await cache.asyncWrite {
                    cache.add(data, update: .modified)
                }
            }.value
        } catch {
            GDLogSpatialDataWarn("Unable to store tile (\(tile.x), \(tile.y), \(tile.zoom))")
        }
        
        GDLogSpatialDataVerbose("Tile Add/Update: (\(tile.x), \(tile.y), \(tile.zoom))")
    }
    
    @SpatialDataCache
    static func extendTileExpiration(_ tile: VectorTile) async {
        await Task {
            do {
                let cache = try await RealmHelper.getCacheRealm(actor: SpatialDataCache.shared)
                
                guard let existingTile = cache.object(ofType: TileData.self, forPrimaryKey: tile.quadKey) else {
                    return
                }
                
                try await cache.asyncWrite {
                    existingTile.ttl = TileData.getNewExpiration()
                }
            } catch {
                GDLogSpatialDataWarn("Unable to extend tile's expiration (\(tile.x), \(tile.y), \(tile.zoom))")
            }
        }.value
    }
    
    @SpatialDataCache
    static func expireAllTiles() async {
        GDLogAppInfo("Expiring all stored tiles")
        
        await Task {
            do {
                let cache = try await RealmHelper.getCacheRealm(actor: SpatialDataCache.shared)
                let tiles = cache.objects(TileData.self)
                
                try await cache.asyncWrite {
                    for tile in tiles {
                        tile.ttl = TileData.getExpiredTtl()
                    }
                }
            } catch {
                GDLogAppError("Unable to expire all tiles...")
            }
        }.value
    }
}
