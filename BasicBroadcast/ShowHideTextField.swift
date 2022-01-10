//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import UIKit

class ShowHideTextField: UITextField {

    private let ShowText = "Show"
    private let HideText = "Hide"

    private var toggleButton = UIButton(frame: .zero)

    override func awakeFromNib() {
        super.awakeFromNib()
        self.isSecureTextEntry = true

        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.setTitle(ShowText, for: .normal)
        toggleButton.setTitleColor(.systemBlue, for: .normal)
        toggleButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
        toggleButton.addTarget(self, action: #selector(toggleVisibility(_:)), for: .touchUpInside)

        self.rightViewMode = .always
        self.rightView = toggleButton
    }

    @objc
    private func toggleVisibility(_ sender: UIButton?) {
        if !self.isFirstResponder {
            self.resignFirstResponder()
        }
        self.isSecureTextEntry.toggle()
        toggleButton.setTitle(self.isSecureTextEntry ? ShowText : HideText, for: .normal)
    }
}
