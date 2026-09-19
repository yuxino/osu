import UIKit
import ReplayKit

final class CapturePermissionController: UIViewController, UIAdaptivePresentationControllerDelegate {
  var onCancelled: (() -> Void)?
  private var completed = false
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .systemBackground
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 22
    stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
    NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)])
    func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
      let label = UILabel(); label.text = text; label.numberOfLines = 0; label.font = .preferredFont(forTextStyle: style); label.adjustsFontForContentSizeCategory = true; return label
    }
    stack.addArrangedSubview(label("允许 Osu 听到 App 的声音", style: .title2))
    stack.addArrangedSubview(label("点下方圆形按钮，在系统面板中选择 Osu Audio，再点「开始广播」。", style: .body))
    let row = UIStackView(); row.alignment = .center; row.distribution = .equalCentering
    row.addArrangedSubview(UIView())
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    picker.preferredExtension = "com.yuxino.osu.MimiBroadcast"; picker.showsMicrophoneButton = false; picker.tintColor = .label
    picker.accessibilityLabel = "允许收音，打开 Osu Audio 系统广播确认"
    picker.widthAnchor.constraint(equalToConstant: 64).isActive = true; picker.heightAnchor.constraint(equalToConstant: 64).isActive = true
    row.addArrangedSubview(picker); row.addArrangedSubview(UIView()); stack.addArrangedSubview(row)
    let explanation = label("iOS 将跨 App 收音称为「屏幕广播」，每次需要你确认。Osu 只处理 App 声音，丢弃视频和麦克风数据，不保存录音或字幕。", style: .footnote)
    explanation.textColor = .secondaryLabel; stack.addArrangedSubview(explanation)
    let cancel = UIButton(type: .system); var config = UIButton.Configuration.gray(); config.title = "暂不开启"; config.baseForegroundColor = .label; cancel.configuration = config
    cancel.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside); stack.addArrangedSubview(cancel)
    presentationController?.delegate = self
  }
  func connected(completion: @escaping () -> Void) { completed = true; dismiss(animated: true, completion: completion) }
  @objc private func cancelPressed() { completed = true; let cancel = onCancelled; dismiss(animated: true) { cancel?() } }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { if !completed { onCancelled?() } }
}
