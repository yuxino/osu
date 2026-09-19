import UIKit

final class CloudCredentialController: UIViewController, UITextFieldDelegate {
  private let hasSavedKey: Bool
  private let saveKey: (String) throws -> Void
  private let removeKey: () throws -> Void
  private let onChanged: (Bool) -> Void
  private let field = UITextField()
  private let feedback = UILabel()
  private let saveButton = UIButton(type: .system)

  init(hasSavedKey: Bool, save: @escaping (String) throws -> Void, remove: @escaping () throws -> Void, onChanged: @escaping (Bool) -> Void) {
    self.hasSavedKey = hasSavedKey; saveKey = save; removeKey = remove; self.onChanged = onChanged
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }

  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .systemBackground
    title = "阿里云密钥"
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancel))
    navigationController?.navigationBar.tintColor = .label
    let scroll = UIScrollView(); scroll.keyboardDismissMode = .interactive; scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
    func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
      let l = UILabel(); l.text = text; l.numberOfLines = 0; l.font = .preferredFont(forTextStyle: style); l.adjustsFontForContentSizeCategory = true; return l
    }
    let heading = label(hasSavedKey ? "更换你的密钥" : "连接阿里云同传", style: .title2); heading.accessibilityTraits.insert(.header); stack.addArrangedSubview(heading)
    let description = label("使用百炼北京地域的 API Key。开启收音后，音频会发送到阿里云，由你的账户计费。", style: .subheadline); description.textColor = .secondaryLabel; stack.addArrangedSubview(description)
    let fieldTitle = label("API Key", style: .headline); stack.addArrangedSubview(fieldTitle); stack.setCustomSpacing(8, after: fieldTitle)
    field.placeholder = hasSavedKey ? "粘贴新的 API Key" : "粘贴 API Key"
    field.accessibilityLabel = "API Key"; field.accessibilityIdentifier = "credential.input"
    field.isSecureTextEntry = true; field.autocorrectionType = .no; field.autocapitalizationType = .none; field.spellCheckingType = .no; field.smartQuotesType = .no; field.smartDashesType = .no
    field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true; field.returnKeyType = .done; field.enablesReturnKeyAutomatically = true; field.delegate = self
    field.backgroundColor = .secondarySystemBackground; field.layer.cornerRadius = 12
    field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1)); field.leftViewMode = .always
    field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1)); field.rightViewMode = .always
    field.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
    field.addTarget(self, action: #selector(edited), for: .editingChanged); stack.addArrangedSubview(field)
    feedback.numberOfLines = 0; feedback.font = .preferredFont(forTextStyle: .footnote); feedback.adjustsFontForContentSizeCategory = true; feedback.accessibilityIdentifier = "credential.feedback"; feedback.isHidden = true; stack.addArrangedSubview(feedback); stack.setCustomSpacing(8, after: field)
    let privacy = label(hasSavedKey ? "已有密钥保存在这台设备的系统钥匙串中。保存新密钥后才会替换。" : "密钥仅保存在这台设备的系统钥匙串中。", style: .footnote); privacy.textColor = .secondaryLabel; stack.addArrangedSubview(privacy)
    let help = UIButton(type: .system); var helpConfig = UIButton.Configuration.plain(); helpConfig.title = "如何获取 API Key"; helpConfig.baseForegroundColor = .label; helpConfig.image = UIImage(systemName: "arrow.up.right"); helpConfig.imagePlacement = .trailing; helpConfig.imagePadding = 8; help.configuration = helpConfig; help.contentHorizontalAlignment = .leading; help.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    help.addAction(UIAction { _ in UIApplication.shared.open(URL(string: "https://help.aliyun.com/zh/model-studio/get-api-key")!) }, for: .touchUpInside); stack.addArrangedSubview(help)
    if hasSavedKey {
      let remove = UIButton(type: .system); var c = UIButton.Configuration.plain(); c.title = "移除已保存密钥"; c.baseForegroundColor = .systemRed; remove.configuration = c; remove.contentHorizontalAlignment = .leading; remove.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      remove.addTarget(self, action: #selector(confirmRemoval), for: .touchUpInside); stack.addArrangedSubview(remove)
    }
    var config = UIButton.Configuration.filled(); config.title = "保存密钥"; config.baseBackgroundColor = .label; config.baseForegroundColor = .systemBackground; config.cornerStyle = .medium; config.contentInsets = .init(top: 16, leading: 24, bottom: 16, trailing: 24); saveButton.configuration = config
    saveButton.accessibilityIdentifier = "credential.save"; saveButton.addTarget(self, action: #selector(save), for: .touchUpInside); saveButton.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(saveButton)
    saveButton.setContentCompressionResistancePriority(.required, for: .vertical)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
      saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), saveButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16), saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
    ])
    edited()
  }
  @objc private func edited() {
    let value = field.text ?? "", valid = CloudCredentialStore.isValid(value)
    saveButton.isEnabled = valid
    feedback.text = "请粘贴完整的 API Key，不要包含空格或换行。"
    feedback.textColor = .secondaryLabel; feedback.isHidden = value.isEmpty || valid
    // Avoid silently losing a pasted key through an accidental sheet swipe.
    navigationController?.isModalInPresentation = !value.isEmpty
  }
  @objc private func save() {
    let value = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard CloudCredentialStore.isValid(value) else { edited(); return }
    do { try saveKey(value); field.text = ""; view.endEditing(true); dismiss(animated: true) { [onChanged] in onChanged(true) } }
    catch { showError("未能保存到系统钥匙串。输入已保留，请重试。") }
  }
  @objc private func cancel() { field.text = ""; view.endEditing(true); dismiss(animated: true) }
  @objc private func confirmRemoval() {
    let alert = UIAlertController(title: "移除密钥？", message: "移除后，需要重新添加密钥才能使用阿里云同传。", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "保留", style: .cancel))
    alert.addAction(UIAlertAction(title: "移除", style: .destructive) { [weak self] _ in
      guard let self else { return }
      do { try self.removeKey(); self.field.text = ""; self.dismiss(animated: true) { [onChanged = self.onChanged] in onChanged(false) } }
      catch { self.showError("未能移除密钥，请重试。") }
    }); present(alert, animated: true)
  }
  private func showError(_ text: String) {
    feedback.text = text; feedback.textColor = .systemRed; feedback.isHidden = false
    UIAccessibility.post(notification: .announcement, argument: text)
  }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool { if saveButton.isEnabled { save() }; return false }
}
