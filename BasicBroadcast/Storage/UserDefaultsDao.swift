//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import Foundation

class UserDefaultsDao {

    let userDefaults: UserDefaults

    init() {
        // This will need to be changed to your own app group. Otherwise
        // ScreenCapture (ReplayKit) won't be able to use credentials entered in the main app.
        // You can always hard code values in this demo though.
        guard let userDefaults = UserDefaults(suiteName: "group.com.example.amazon-samplecode.BasicBroadcast") else {
            fatalError("No access no shared user defaults")
        }
        self.userDefaults = userDefaults
    }

}
