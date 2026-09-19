import UIKit
import ReplayKit

final class CapturePermissionController: UIViewController, UIAdaptivePresentationControllerDelegate {
  var onCancelled: (() -> Void)?
  private var completed = false
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .systemBackground
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
    scroll.alwaysBounceVertical = true
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 22
    stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
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
    picker.subviews.compactMap { $0 as? UIButton }.forEach { $0.accessibilityLabel = "允许收音"; $0.accessibilityHint = "打开系统面板，选择 Osu Audio 并开始广播" }
    picker.widthAnchor.constraint(equalToConstant: 64).isActive = true; picker.heightAnchor.constraint(equalToConstant: 64).isActive = true
    row.addArrangedSubview(picker); row.addArrangedSubview(UIView()); stack.addArrangedSubview(row)
    let explanation = label("开始后请回到视频 App 内播放。视频小窗会替换 Osu 的字幕小窗。\n\niOS 将跨 App 收音称为「屏幕广播」，每次需要你确认。Osu 只处理 App 声音，丢弃视频和麦克风数据，不保存录音或字幕。", style: .footnote)
    explanation.textColor = .secondaryLabel; stack.addArrangedSubview(explanation)
    let cancel = UIButton(type: .system); var config = UIButton.Configuration.gray(); config.title = "暂不开启"; config.baseForegroundColor = .label; cancel.configuration = config
    cancel.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
    cancel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(cancel)
    cancel.setContentCompressionResistancePriority(.required, for: .vertical)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: cancel.topAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
      stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -28),
      cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
    ])
    presentationController?.delegate = self
  }
  func connected(completion: @escaping () -> Void) { completed = true; dismiss(animated: true, completion: completion) }
  @objc private func cancelPressed() { completed = true; let cancel = onCancelled; dismiss(animated: true) { cancel?() } }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { if !completed { onCancelled?() } }
}
