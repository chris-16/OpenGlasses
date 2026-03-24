import Foundation
import UIKit

/// Native tool for launching Chinese apps and services via URL schemes.
/// Supports WeChat, Alipay, Baidu Maps, Amap (Gaode), QQ, Weibo, Douyin,
/// DingTalk, Taobao, Meituan, Dianping, Xiaohongshu, Bilibili, Ele.me, and Ctrip.
struct ChineseAppsTool: NativeTool {
    let name = "chinese_app"
    let description = """
        Open Chinese apps and services. Supports: WeChat (微信), Alipay (支付宝), \
        Baidu Maps (百度地图), Amap/Gaode (高德地图), QQ, Weibo (微博), Douyin (抖音), \
        DingTalk (钉钉), Taobao (淘宝), Meituan (美团), Dianping (大众点评), \
        Xiaohongshu/RED (小红书), Bilibili (B站), Ele.me (饿了么), Ctrip (携程). \
        Use when the user asks to open a Chinese app, send a WeChat message, scan with Alipay, \
        navigate with Baidu Maps, etc.
        """

    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "app": [
                "type": "string",
                "description": "App name: 'wechat', 'alipay', 'baidumap', 'amap', 'qq', 'weibo', 'douyin', 'dingtalk', 'taobao', 'meituan', 'dianping', 'xiaohongshu', 'bilibili', 'eleme', 'ctrip'",
                "enum": ["wechat", "alipay", "baidumap", "amap", "qq", "weibo", "douyin", "dingtalk", "taobao", "meituan", "dianping", "xiaohongshu", "bilibili", "eleme", "ctrip"]
            ],
            "action": [
                "type": "string",
                "description": "Optional action: 'open' (default), 'scan' (QR scanner), 'pay' (payment), 'navigate' (for maps, requires 'query')"
            ],
            "query": [
                "type": "string",
                "description": "Search query or destination (for maps navigation or app search)"
            ]
        ],
        "required": ["app"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let appName = args["app"] as? String else {
            return "请指定要打开的应用名称。"
        }
        let action = (args["action"] as? String) ?? "open"
        let query = args["query"] as? String

        let urlString: String
        let displayName: String

        switch appName.lowercased() {
        case "wechat", "weixin":
            displayName = "微信"
            switch action {
            case "scan": urlString = "weixin://scanqrcode"
            default: urlString = "weixin://"
            }

        case "alipay":
            displayName = "支付宝"
            switch action {
            case "scan": urlString = "alipayqr://platformapi/startapp?saId=10000007"
            case "pay": urlString = "alipays://platformapi/startapp?saId=20000056"
            default: urlString = "alipay://"
            }

        case "baidumap":
            displayName = "百度地图"
            if let q = query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString = "baidumap://map/geocoder?src=openglasses&address=\(q)"
            } else {
                urlString = "baidumap://"
            }

        case "amap", "gaode":
            displayName = "高德地图"
            if let q = query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString = "iosamap://poi?sourceApplication=openglasses&keywords=\(q)"
            } else {
                urlString = "iosamap://"
            }

        case "qq":
            displayName = "QQ"
            urlString = "mqq://"

        case "weibo":
            displayName = "微博"
            urlString = "sinaweibo://"

        case "douyin":
            displayName = "抖音"
            urlString = "snssdk1128://"

        case "dingtalk":
            displayName = "钉钉"
            urlString = "dingtalk://"

        case "taobao":
            displayName = "淘宝"
            if let q = query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString = "taobao://s.taobao.com/?q=\(q)"
            } else {
                urlString = "taobao://"
            }

        case "meituan":
            displayName = "美团"
            urlString = "imeituan://"

        case "dianping":
            displayName = "大众点评"
            urlString = "dianping://"

        case "xiaohongshu", "red":
            displayName = "小红书"
            urlString = "xhsdiscover://"

        case "bilibili":
            displayName = "Bilibili"
            if let q = query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString = "bilibili://search?keyword=\(q)"
            } else {
                urlString = "bilibili://"
            }

        case "eleme":
            displayName = "饿了么"
            urlString = "eleme://"

        case "ctrip":
            displayName = "携程"
            urlString = "ctrip://"

        default:
            return "不支持的应用: \(appName)。支持的应用: 微信、支付宝、百度地图、高德地图、QQ、微博、抖音、钉钉、淘宝、美团、大众点评、小红书、Bilibili、饿了么、携程。"
        }

        guard let url = URL(string: urlString) else {
            return "无法生成 \(displayName) 的链接。"
        }

        let opened = await MainActor.run {
            UIApplication.shared.canOpenURL(url)
        }

        if opened {
            await MainActor.run {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            let actionDesc: String
            switch action {
            case "scan": actionDesc = "扫一扫"
            case "pay": actionDesc = "付款"
            case "navigate": actionDesc = "导航"
            default: actionDesc = ""
            }
            return "正在打开\(displayName)\(actionDesc.isEmpty ? "" : " — \(actionDesc)")。"
        } else {
            return "\(displayName)未安装。请先从 App Store 安装。"
        }
    }
}
