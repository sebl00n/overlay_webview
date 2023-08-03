import Cocoa
import FlutterMacOS
import WebKit

public class OverlayWebviewPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    var methodChannel :FlutterMethodChannel
    var eventChannel :FlutterEventChannel
    
    var eventSink: FlutterEventSink?
    var webviews = Dictionary<String, WebviewManager>();

    var mainWindow :NSWindow?;
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        _ = OverlayWebviewPlugin(registrar: registrar)
    }
    
    init(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(name: "overlay_webview", binaryMessenger: registrar.messenger)
        eventChannel = FlutterEventChannel(name: "overlay_webview_events", binaryMessenger: registrar.messenger)
        
        super.init()
        
        registrar.addMethodCallDelegate(self, channel: methodChannel)
        eventChannel.setStreamHandler(self)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

        if(mainWindow == nil) {
            mainWindow = NSApplication.shared.mainWindow;
        }

        let args = call.arguments as! NSDictionary;
        let webviewID : String = args["id"] != nil ? args["id"] as! String : "";
        
        if(call.method == "init") {
            if(webviews[webviewID] == nil) {
                webviews[webviewID] = WebviewManager(id: webviewID, plugin: self)
            } else {
                webviews[webviewID]?.hide()
            }
        }
        else if(call.method == "dispose") {
            webviews[webviewID]?.dispose()
            webviews.removeValue(forKey: webviewID)
        }
        else if(call.method == "show") {
            webviews[webviewID]?.show()
        }
        else if(call.method == "hide") {
            webviews[webviewID]?.hide()
        }
        else if(call.method == "reload") {
            webviews[webviewID]?.reload()
        }
        else if(call.method == "back") {
            webviews[webviewID]?.back()
        }
        else if(call.method == "forward") {
            webviews[webviewID]?.forward()
        }
        else if(call.method == "load") {
            let url = (call.arguments as! NSDictionary)["url"] as! String
            webviews[webviewID]?.load(url: url)
        }
        else if(call.method == "loadHTML") {
            let html = (call.arguments as! NSDictionary)["html"] as! String
            webviews[webviewID]?.loadHTML(html: html)
        }
        else if(call.method == "errorPage") {
            let html = (call.arguments as! NSDictionary)["html"] as! String
            webviews[webviewID]?.errorPage = html
        }
        else if(call.method == "position") {
            let rect = call.arguments as! NSDictionary
            let l = rect["l"] as! CGFloat
            let t = rect["t"] as! CGFloat
            let w = rect["w"] as! CGFloat
            let h = rect["h"] as! CGFloat
            webviews[webviewID]?.position(l: l, t: t, w: w, h: h)
        }
        else if(call.method == "denyList") {
            webviews[webviewID]?.setDenyList(patterns: args["items"] as! Dictionary<String, String>)
        }
        else if(call.method == "exec") {
            let exec_id = (call.arguments as! NSDictionary)["exec_id"] as! String
            let expression = (call.arguments as! NSDictionary)["expression"] as! String
            webviews[webviewID]?.eval(exec_id: exec_id, expression: expression)
        }
        else if(call.method == "activeWebViews") {
            result(Array(webviews.keys))
            return
        }
        else if(call.method == "disposeAll") {
            for key in webviews.keys {
                webviews[key]?.dispose()
            }
            webviews.removeAll()
        }
        else if(call.method == "clearCookies") {
            if #available(macOS 10.13, *) {
                let cookieStore = WKWebsiteDataStore.default().httpCookieStore
                cookieStore.getAllCookies {
                    cookies in
                    for cookie in cookies {
                        cookieStore.delete(cookie)
                    }
                }
            }
        }
        else if(call.method == "enableDebugging") {
        }
        else {
            result(FlutterMethodNotImplemented)
            return
        }
        result(nil)
    }
    
    public func sendEvent(id: String, type: String, data: Dictionary<String, Any?>) {
        if (eventSink == nil) {
            return
        }
        let event:NSDictionary = [
            "id": id,
            "type" : type,
            "data" : data,
        ]
        eventSink?(event)
    }
    
    public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

public class WebviewManager : NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let plugin: OverlayWebviewPlugin
    let id : String
    let webview : WKWebView
    var errorPage: String?
    
    var denyPatterns: Dictionary<String, String>?
    
    // For giving back page with error
    var _lastURL = ""
    
    public init(id: String, plugin: OverlayWebviewPlugin) {
        self.id = id;
        self.plugin = plugin;
        
        let webCfg:WKWebViewConfiguration = WKWebViewConfiguration()
        let userController:WKUserContentController = WKUserContentController()
        webCfg.userContentController = userController;
        
        let view = plugin.mainWindow?.contentViewController?.view
        var rect : CGRect?
        if view != nil {
            rect = CGRect(x: 0, y: 0, width: view!.frame.size.width, height: view!.frame.size.height)
        } else {
            rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        }
        webview = WKWebView(frame: rect!, configuration: webCfg);
        
        super.init()
        
        userController.add(self, name: "WebViewBridge")
        
        webview.navigationDelegate = self
        webview.uiDelegate = self
    }
    
    public func rootView() -> NSView? {
        /*if(self.plugin.mainWindow == nil){
            //print("Main Window is nil")
        }
        else if(NSApplication.shared.mainWindow?.contentViewController == nil){
            //print("ContentViewController is nil")
        }
        else if(NSApplication.shared.mainWindow?.contentViewController?.view == nil){
            //print("CV View is nil")
        }*/
        return self.plugin.mainWindow?.contentViewController?.view
    }
    
    public func dispose() {
        hide()
    }
    
    public func show() {
        let view = self.rootView()
        if view != nil {
            view!.addSubview(webview)
            webview.isHidden = false
        }
    }
    
    public func hide() {
        webview.removeFromSuperview()
        if let v = self.plugin.mainWindow?.contentViewController?.view {
            NSApplication.shared.mainWindow?.selectKeyView(following: v)
            print("hide")
        }
        //webview.dein
    }
    
    public func load(url: String) {
        webview.load(URLRequest(url: URL(string: url)!))
    }
    
    public func loadHTML(html: String) {
        webview.loadHTMLString(html, baseURL: nil)
    }
    
    public func back() {
        webview.goBack()
    }
    
    public func forward() {
        webview.goForward()
    }
    
    public func reload() {
        webview.reload()
    }
    
    public func position(l: CGFloat, t: CGFloat, w: CGFloat, h: CGFloat) {
         //CUSTOM BEGIN: Sebi -> Berechnen der Y Pos

        let view = self.rootView()
            if(view == nil) {
             print("Positioning but view is nil")
         }
        let y = (view?.frame.size.height ?? 100) /*NSScreen.main!.visibleFrame.size.height*/ - t - h;
        webview.frame = CGRect(x: l, y: y, width: w, height: h)
        print(l)
        print(y)
        print(w)
        print(h)
        //CUSTOM END: Sebi -> Berechnen der Y Pos
    }
    
    public func setDenyList(patterns: Dictionary<String, String>) {
        self.denyPatterns = patterns
    }
    
    public func eval(exec_id: String, expression: String) {
        webview.evaluateJavaScript(expression) { (result, error) in
            self.plugin.sendEvent(id: self.id, type: "exec_result", data: [
                "id": exec_id,
                "result": result,
            ])
            return
        }
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if(message.body is String){
            self.plugin.sendEvent(id: id, type: "post_message", data: [
                "message": message.body,
            ])
        }
    }
    
    public func webView(_ _: WKWebView, didFinish navigation: WKNavigation!) {
        plugin.sendEvent(id: id, type: "page_end", data: [
            "url": webview.url!.absoluteString,
            "can_go_back": webview.canGoBack,
            "can_go_forward": webview.canGoBack,
        ])
    }
    
    public func webView(_ _: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        plugin.sendEvent(id: id, type: "page_start", data: [
            "url": webview.url!.absoluteString,
            "can_go_back": webview.canGoBack,
            "can_go_forward": webview.canGoBack,
        ])
        _lastURL = webview.url!.absoluteString
    }
    
    public func webView(_ _: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        plugin.sendEvent(id: id, type: "page_error", data: [
            "url": _lastURL,
            "code": String((error as NSError).code),
            "description": error.localizedDescription,
            "can_go_back": webview.canGoBack,
            "can_go_forward": webview.canGoBack,
        ])
        if(errorPage != nil) {
            var html = errorPage!
            html = html.replacingOccurrences(of: "{{errorURL}}", with: _lastURL)
            html = html.replacingOccurrences(of: "{{errorCode}}", with: String((error as NSError).code))
            html = html.replacingOccurrences(of: "{{errorDescription}}", with: error.localizedDescription)
            
            loadHTML(html: html)
        }
    }
    
    public func webView(_ _: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        plugin.sendEvent(id: id, type: "page_error", data: [
            "url": _lastURL,
            "code": String((error as NSError).code),
            "description": error.localizedDescription,
            "can_go_back": webview.canGoBack,
            "can_go_forward": webview.canGoBack,
        ])
        if(errorPage != nil) {
            var html = errorPage!
            html = html.replacingOccurrences(of: "{{errorURL}}", with: _lastURL)
            html = html.replacingOccurrences(of: "{{errorCode}}", with: String((error as NSError).code))
            html = html.replacingOccurrences(of: "{{errorDescription}}", with: error.localizedDescription)
            
            loadHTML(html: html)
        }
    }
    
    public func webView(_ _: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Swift.Void) {
        
        plugin.sendEvent(id: id, type: "page_progress", data: [
            "url": navigationAction.request.url!.absoluteString,
            "can_go_back": webview.canGoBack,
            "can_go_forward": webview.canGoBack,
        ])
        
        if denyPatterns != nil {
            for key in denyPatterns!.keys {
                let match = navigationAction.request.url!.absoluteString.range(of: denyPatterns![key]!, options: .regularExpression) != nil
                
                if(match) {
                    plugin.sendEvent(id: id, type: "page_deny", data: [
                        "key": key,
                        "url": navigationAction.request.url!.absoluteString,
                        "can_go_back": webview.canGoBack,
                        "can_go_forward": webview.canGoBack,
                    ])
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        
        if navigationAction.navigationType == WKNavigationType.linkActivated && navigationAction.targetFrame == nil {
            plugin.sendEvent(id: id, type: "page_new_window", data: [
                "url": navigationAction.request.url!.absoluteString,
                "can_go_back": webview.canGoBack,
                "can_go_forward": webview.canGoBack,
            ])
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {

            // Set the message as the NSAlert text
            let alert = NSAlert()
            alert.messageText = message
//            alert.informativeText = message
            alert.addButton(withTitle: "Ok")

            // Display the NSAlert
            alert.runModal()

            // Call completionHandler
            completionHandler()
        }


        public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            // Set the message as the NSAlert text
            let alert = NSAlert()
            alert.messageText = message

            // Add a confirmation button “OK”
            // and cancel button “Cancel”
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            // Display the NSAlert
            let action = alert.runModal()

            // Call completionHandler with true only
            // if the user selected OK (the first button)
            completionHandler(action == .alertFirstButtonReturn)
        }


        public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            
            // Set the prompt as the NSAlert text
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "Submit")

            // Add an input NSTextField for the prompt
            let inputFrame = NSRect(
                x: 0,
                y: 0,
                width: 300,
                height: 24
            )

            let textField = NSTextField(frame: inputFrame)
            textField.placeholderString = (defaultText)
            alert.accessoryView = textField

            // Display the NSAlert
            alert.runModal()

            // Call completionHandler with
            // the user input from textField
            completionHandler(textField.stringValue)
        }
}
