//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import Foundation

/// A simple UserDefaults based storage class to store and recall previously used endpoint / stream key pairs.
class UserDefaultsAuthDao: UserDefaultsDao {
    
    static let shared = UserDefaultsAuthDao()
    
    private let UserDefaultsKey = "UserDefaultsAuthDaoKey"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var authItems = [AuthItem]()
    
    private override init() {
        super.init()
        if let data = userDefaults.data(forKey: UserDefaultsKey), let items = try? decoder.decode([AuthItem].self, from: data) {
            authItems = items
        }
    }
    
    func fetchAll() -> [AuthItem] {
        return authItems
    }

    func lastUsedAuth() -> AuthItem? {
        return fetchAll().last
    }
    
    func insert(_ authItem: AuthItem) {
        authItems.removeAll { $0.endpoint == authItem.endpoint }
        authItems.append(authItem)
        if let data = try? encoder.encode(authItems) {
            userDefaults.set(data, forKey: UserDefaultsKey)
        }
    }
}
