import UIKit

/// Exercises real UIKit actions with a disposable in-memory key, never Keychain.
@MainActor final class InteractionFixture {
  private var key: String?
  private var failNextSave = true
  private var saves = 0
  func controller() -> MimiPrototypeController {
    UserDefaults.standard.set(true, forKey: "osu.automaticLanguageDefaultsV1")
    UserDefaults.standard.set("alibaba", forKey: "mimi.engine")
    UserDefaults.standard.set("auto", forKey: "mimi.alibaba.source")
    UserDefaults.standard.set("zh", forKey: "mimi.alibaba.target")
    UserDefaults.standard.set(false, forKey: "osu.showOriginalSubtitles")
    return MimiPrototypeController(readCloudCredential: { [self] in key }, saveCloudCredential: { [self] value in
      saves += 1
      if failNextSave { failNextSave = false; throw CloudCredentialStore.Failure.unavailable }
      key = value
    }, removeCloudCredential: { [self] in key = nil }, requestBroadcast: { true })
  }
  func run(_ controller: MimiPrototypeController, completion: @escaping (Bool, String) -> Void) {
    Task { @MainActor in
      do {
        try await wait { UIApplication.shared.applicationState == .active }
        controller.view.layoutIfNeeded()
        let primary: UIButton = try find("home.primary", in: controller.view)
        let settings: UIButton = try find("home.settings", in: controller.view)
        let frame = primary.convert(primary.bounds, to: controller.view)
        guard controller.view.safeAreaLayoutGuide.layoutFrame.contains(frame), frame.height >= 48 else { throw fail("primary_outside_safe_area") }
        let scroll = descendants(controller.view).compactMap { $0 as? UIScrollView }.first!
        scroll.contentOffset = CGPoint(x: 0, y: max(100, scroll.contentSize.height - scroll.bounds.height))
        controller.view.layoutIfNeeded()
        guard primary.convert(primary.bounds, to: controller.view) == frame, controller.view.safeAreaLayoutGuide.layoutFrame.contains(settings.convert(settings.bounds, to: controller.view)) else { throw fail("actions_scroll_away") }
        scroll.contentOffset = .zero

        primary.sendActions(for: .touchUpInside)
        try await wait { controller.presentedViewController is UINavigationController }
        let editor = (controller.presentedViewController as! UINavigationController).topViewController!
        let input: UITextField = try find("credential.input", in: editor.view)
        let save: UIButton = try find("credential.save", in: editor.view)
        guard !save.isEnabled else { throw fail("empty_key_save_enabled") }
        input.text = "bad"; input.sendActions(for: .editingChanged)
        guard !save.isEnabled else { throw fail("invalid_key_save_enabled") }
        input.text = " fixture-only-key "; input.sendActions(for: .editingChanged)
        guard save.isEnabled else { throw fail("valid_key_save_disabled") }
        save.sendActions(for: .touchUpInside)
        let feedback: UILabel = try find("credential.feedback", in: editor.view)
        guard key == nil, input.text == " fixture-only-key ", !feedback.isHidden, feedback.text?.contains("输入已保留") == true else { throw fail("failed_save_lost_input_or_feedback") }
        save.sendActions(for: .touchUpInside)
        try await wait { controller.presentedViewController == nil }
        guard key == "fixture-only-key", saves == 2, input.text == "", primary.configuration?.title == "开始听" else { throw fail("save_retry_did_not_update_home") }

        let original: UIButton = try find("home.original", in: controller.view)
        original.sendActions(for: .touchUpInside)
        settings.sendActions(for: .touchUpInside)
        try await wait { controller.presentedViewController != nil }
        let page = controller.presentedViewController!
        let toggle = descendants(page.view).compactMap { $0 as? UISwitch }.first!
        guard toggle.isOn, UserDefaults.standard.bool(forKey: "osu.showOriginalSubtitles") else { throw fail("home_original_not_synced") }
        toggle.isOn = false; toggle.sendActions(for: .valueChanged)
        guard original.accessibilityValue == "已关闭", !UserDefaults.standard.bool(forKey: "osu.showOriginalSubtitles") else { throw fail("settings_original_not_synced") }
        try press("阿里云密钥", in: page.view)
        try await wait { page.presentedViewController is UINavigationController }
        let replacement = (page.presentedViewController as! UINavigationController).topViewController!
        let replacementInput: UITextField = try find("credential.input", in: replacement.view)
        replacementInput.text = "discarded-fixture-key"; replacementInput.sendActions(for: .editingChanged)
        let cancel = replacement.navigationItem.leftBarButtonItem!
        UIApplication.shared.sendAction(cancel.action!, to: cancel.target, from: cancel, for: nil)
        try await wait { page.presentedViewController == nil }
        guard key == "fixture-only-key", replacementInput.text == "" else { throw fail("cancel_changed_saved_key") }
        try press("阿里云密钥", in: page.view)
        try await wait { page.presentedViewController is UINavigationController }
        let removal = (page.presentedViewController as! UINavigationController).topViewController!
        try press("移除已保存密钥", in: removal.view)
        try await wait { removal.presentedViewController is UIAlertController }
        guard key != nil else { throw fail("removal_without_confirmation") }
        // Alert actions are verified through actual UI separately. Dismiss keeps the key.
        removal.presentedViewController?.dismiss(animated: false)
        removal.dismiss(animated: false)
        try await wait { page.presentedViewController == nil }
        try press("完成", in: page.view)
        try await wait { controller.presentedViewController == nil }
        completion(true, "pinned_actions_invalid_key_failed_save_retry_cancel_original_sync_removal_confirmation")
      } catch { completion(false, (error as NSError).domain) }
    }
  }
  private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
  private func find<T: UIView>(_ id: String, in view: UIView) throws -> T {
    guard let result = descendants(view).first(where: { $0.accessibilityIdentifier == id }) as? T else { throw fail("missing_" + id) }; return result
  }
  private func press(_ title: String, in view: UIView) throws {
    guard let button = descendants(view).compactMap({ $0 as? UIButton }).first(where: { $0.configuration?.title == title && $0.isEnabled && !$0.isHidden }) else { throw fail("missing_action_" + title) }
    button.sendActions(for: .touchUpInside)
  }
  private func wait(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(4)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
    guard condition() else { throw fail("interaction_timeout") }
    try await Task.sleep(nanoseconds: 400_000_000)
  }
  private func fail(_ name: String) -> NSError { NSError(domain: name, code: 1) }
}
