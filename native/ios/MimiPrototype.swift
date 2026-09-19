import UIKit
import React

@objc(MimiPrototype)
class MimiPrototype: NSObject {
  @objc static func requiresMainQueueSetup() -> Bool { true }
  @objc func open() {
    DispatchQueue.main.async {
      guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else { return }
      var top = root
      while let presented = top.presentedViewController { top = presented }
      guard !(top is MimiPrototypeController) else { return }
      let controller = MimiPrototypeController()
      controller.modalPresentationStyle = .fullScreen
      top.present(controller, animated: false)
    }
  }
}
