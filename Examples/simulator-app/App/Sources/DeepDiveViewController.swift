import UIKit

private struct DeepDiveMetricItem {
    let title: String
    let value: String
    let tint: UIColor
}

private struct DeepDiveTimelineItem {
    let time: String
    let title: String
    let detail: String
    let level: String
}

private final class DeepDiveMetricChipView: UIView {
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()

    init(item: DeepDiveMetricItem) {
        super.init(frame: .zero)
        layout(item: item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func layout(item: DeepDiveMetricItem) {
        backgroundColor = item.tint
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0.45, green: 0.58, blue: 0.72, alpha: 0.22).cgColor

        valueLabel.text = item.value
        valueLabel.font = .systemFont(ofSize: 24, weight: .bold)
        valueLabel.textColor = UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1)
        valueLabel.textAlignment = .left

        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = UIColor(red: 0.66, green: 0.75, blue: 0.85, alpha: 1)
        titleLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 6
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }
}

private final class DeepDiveTimelineItemView: UIView {
    private let timeLabel = UILabel()
    private let levelLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let dotView = UIView()

    init(item: DeepDiveTimelineItem) {
        super.init(frame: .zero)
        layout(item: item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func layout(item: DeepDiveTimelineItem) {
        let tint = levelTint(level: item.level)

        dotView.backgroundColor = tint
        dotView.layer.cornerRadius = 5
        dotView.layer.masksToBounds = true

        let line = UIView()
        line.backgroundColor = UIColor(red: 0.46, green: 0.83, blue: 0.97, alpha: 0.24)

        let rail = UIStackView(arrangedSubviews: [dotView, line])
        rail.axis = .vertical
        rail.spacing = 8
        rail.alignment = .center
        rail.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.text = item.time
        timeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = UIColor(red: 0.97, green: 0.78, blue: 0.45, alpha: 1)

        levelLabel.text = item.level.uppercased()
        levelLabel.font = .systemFont(ofSize: 10, weight: .bold)
        levelLabel.textColor = UIColor(red: 0.02, green: 0.07, blue: 0.11, alpha: 1)
        levelLabel.backgroundColor = tint
        levelLabel.layer.cornerRadius = 10
        levelLabel.layer.masksToBounds = true
        levelLabel.textAlignment = .center
        levelLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        levelLabel.setContentHuggingPriority(.required, for: .horizontal)

        let metaRow = UIStackView(arrangedSubviews: [timeLabel, levelLabel])
        metaRow.axis = .horizontal
        metaRow.spacing = 8
        metaRow.alignment = .center

        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1)
        titleLabel.numberOfLines = 0

        detailLabel.text = item.detail
        detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = UIColor(red: 0.62, green: 0.70, blue: 0.78, alpha: 1)
        detailLabel.numberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping

        let textStack = UIStackView(arrangedSubviews: [metaRow, titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 6

        let root = UIStackView(arrangedSubviews: [rail, textStack])
        root.axis = .horizontal
        root.spacing = 12
        root.alignment = .top
        addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false

        let lineHeight: CGFloat = 1
        NSLayoutConstraint.activate([
            rail.widthAnchor.constraint(equalToConstant: 16),
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10),
            line.widthAnchor.constraint(equalToConstant: 2),
            line.heightAnchor.constraint(equalToConstant: 74),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            levelLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            levelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: lineHeight)
        ])
    }

    private func levelTint(level: String) -> UIColor {
        switch level.lowercased() {
        case "error":
            return UIColor(red: 1.0, green: 0.54, blue: 0.50, alpha: 1)
        case "warn":
            return UIColor(red: 0.97, green: 0.78, blue: 0.45, alpha: 1)
        default:
            return UIColor(red: 0.46, green: 0.83, blue: 0.97, alpha: 1)
        }
    }
}

@MainActor
final class DeepDiveViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let tabButtons: [UIButton]

    private let tabs = ["概览", "链路", "诊断"]
    private let metrics: [DeepDiveMetricItem] = [
        .init(title: "queueSize", value: "12", tint: UIColor(red: 0.14, green: 0.29, blue: 0.42, alpha: 1)),
        .init(title: "ingested", value: "128", tint: UIColor(red: 0.06, green: 0.24, blue: 0.36, alpha: 1)),
        .init(title: "renderNodes", value: "742", tint: UIColor(red: 0.15, green: 0.17, blue: 0.34, alpha: 1)),
        .init(title: "dropped", value: "0", tint: UIColor(red: 0.27, green: 0.18, blue: 0.09, alpha: 1))
    ]

    private let timeline: [DeepDiveTimelineItem] = [
        .init(
            time: "10:42:12",
            title: "Gateway Discovery Started",
            detail: "尝试 mDNS 发现，预期在 300ms 内返回可用 endpoint。",
            level: "info"
        ),
        .init(
            time: "10:42:13",
            title: "Fallback to Manual DSN",
            detail: "mDNS 未命中，回退 127.0.0.1:18765，继续探测 /v2/gateway/discovery。",
            level: "warn"
        ),
        .init(
            time: "10:42:14",
            title: "Raw Inspector Ingested",
            detail: "成功上报原始节点树，网关开始标准化映射与 typography 单位收敛。",
            level: "info"
        ),
        .init(
            time: "10:42:15",
            title: "Snapshot Build Completed",
            detail: "snapshot 构建完成，包含 textContentAlign / padding / wordBreak 全量字段。",
            level: "info"
        )
    ]

    private var selectedTabIndex = 0 {
        didSet {
            refreshSelectedTab()
        }
    }

    init() {
        tabButtons = tabs.map { title in
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = title
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            config.background.backgroundColor = UIColor(white: 1, alpha: 0.08)
            config.baseForegroundColor = UIColor(red: 0.66, green: 0.75, blue: 0.85, alpha: 1)
            button.configuration = config
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            button.layer.cornerRadius = 999
            button.layer.masksToBounds = true
            return button
        }

        super.init(nibName: nil, bundle: nil)
        title = "Neptune Deep Dive"
        tabButtons.enumerated().forEach { index, button in
            button.tag = index
            button.addTarget(self, action: #selector(onTabTap(_:)), for: .touchUpInside)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.06, blue: 0.10, alpha: 1)
        buildViewHierarchy()
        refreshSelectedTab()
    }

    private func buildViewHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28)
        ])

        let headerCard = makeCard()
        let headerStack = UIStackView()
        headerStack.axis = .vertical
        headerStack.spacing = 10

        let titleLabel = makeTitleLabel(text: "Neptune Deep Dive", size: 30)
        let subtitleLabel = makeBodyLabel(
            text: "复杂二级页用于验证视图树采集、文本还原、胶囊标签、时间轴列表和卡片层级表现。"
        )
        subtitleLabel.numberOfLines = 0

        let tabRow = UIStackView(arrangedSubviews: tabButtons)
        tabRow.axis = .horizontal
        tabRow.spacing = 8
        tabRow.distribution = .fillEqually

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)
        headerStack.addArrangedSubview(tabRow)

        headerCard.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -20),
            headerStack.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -20)
        ])

        let metricsCard = makeCard()
        let metricsTitle = makeTitleLabel(text: "Live Metrics Matrix", size: 18)
        let metricsGrid = UIStackView()
        metricsGrid.axis = .vertical
        metricsGrid.spacing = 10
        metricsGrid.addArrangedSubview(UIStackView(arrangedSubviews: [
            DeepDiveMetricChipView(item: metrics[0]),
            DeepDiveMetricChipView(item: metrics[1])
        ]))
        metricsGrid.addArrangedSubview(UIStackView(arrangedSubviews: [
            DeepDiveMetricChipView(item: metrics[2]),
            DeepDiveMetricChipView(item: metrics[3])
        ]))
        for case let row as UIStackView in metricsGrid.arrangedSubviews {
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
        }

        let metricsStack = UIStackView(arrangedSubviews: [metricsTitle, metricsGrid])
        metricsStack.axis = .vertical
        metricsStack.spacing = 12
        metricsCard.addSubview(metricsStack)
        metricsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            metricsStack.topAnchor.constraint(equalTo: metricsCard.topAnchor, constant: 20),
            metricsStack.leadingAnchor.constraint(equalTo: metricsCard.leadingAnchor, constant: 20),
            metricsStack.trailingAnchor.constraint(equalTo: metricsCard.trailingAnchor, constant: -20),
            metricsStack.bottomAnchor.constraint(equalTo: metricsCard.bottomAnchor, constant: -20)
        ])

        let timelineCard = makeCard()
        let timelineTitle = makeTitleLabel(text: "Inspector Timeline", size: 18)
        let timelineStack = UIStackView()
        timelineStack.axis = .vertical
        timelineStack.spacing = 10
        timeline.forEach { timelineStack.addArrangedSubview(DeepDiveTimelineItemView(item: $0)) }

        let timelineContainer = UIStackView(arrangedSubviews: [timelineTitle, timelineStack])
        timelineContainer.axis = .vertical
        timelineContainer.spacing = 12
        timelineCard.addSubview(timelineContainer)
        timelineContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            timelineContainer.topAnchor.constraint(equalTo: timelineCard.topAnchor, constant: 20),
            timelineContainer.leadingAnchor.constraint(equalTo: timelineCard.leadingAnchor, constant: 20),
            timelineContainer.trailingAnchor.constraint(equalTo: timelineCard.trailingAnchor, constant: -20),
            timelineContainer.bottomAnchor.constraint(equalTo: timelineCard.bottomAnchor, constant: -20)
        ])

        [headerCard, metricsCard, timelineCard].forEach(contentStack.addArrangedSubview(_:))
    }

    private func refreshSelectedTab() {
        tabButtons.enumerated().forEach { index, button in
            let selected = index == selectedTabIndex
            var config = button.configuration ?? .filled()
            config.title = tabs[index]
            config.background.backgroundColor = selected ? UIColor(red: 0.46, green: 0.83, blue: 0.97, alpha: 1) : UIColor(white: 1, alpha: 0.08)
            config.baseForegroundColor = selected ? UIColor(red: 0.02, green: 0.07, blue: 0.11, alpha: 1) : UIColor(red: 0.66, green: 0.75, blue: 0.85, alpha: 1)
            button.configuration = config
        }
    }

    @objc private func onTabTap(_ sender: UIButton) {
        selectedTabIndex = sender.tag
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.05, green: 0.10, blue: 0.16, alpha: 0.96)
        card.layer.cornerRadius = 24
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.41, green: 0.56, blue: 0.69, alpha: 0.25).cgColor
        return card
    }

    private func makeTitleLabel(text: String, size: CGFloat) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: .bold)
        label.textColor = UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1)
        label.numberOfLines = 0
        return label
    }

    private func makeBodyLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = UIColor(red: 0.62, green: 0.70, blue: 0.78, alpha: 1)
        label.lineBreakMode = .byWordWrapping
        return label
    }
}
