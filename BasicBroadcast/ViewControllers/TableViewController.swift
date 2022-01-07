//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import AmazonIVSBroadcast
import Foundation
import UIKit

class TableViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "IVS SDK \(IVSBroadcastSession.sdkVersion)"
    }
}
