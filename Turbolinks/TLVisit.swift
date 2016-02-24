import WebKit

protocol TLVisitDelegate: class {
    func visitDidInitializeWebView(visit: TLVisit)

    func visitWillStart(visit: TLVisit)
    func visitDidStart(visit: TLVisit)
    func visitDidComplete(visit: TLVisit)
    func visitDidFail(visit: TLVisit)

    func visitWillLoadResponse(visit: TLVisit)
    func visitDidRender(visit: TLVisit)

    func visitRequestDidStart(visit: TLVisit)
    func visit(visit: TLVisit, requestDidFailWithError error: NSError)
    func visitRequestDidFinish(visit: TLVisit)
}

enum TLVisitState: String {
    case Initialized = "Initialized"
    case Started = "Started"
    case Canceled = "Canceled"
    case Failed = "Failed"
    case Completed = "Completed"
}

class TLVisit: NSObject {
    weak var delegate: TLVisitDelegate?

    var visitable: TLVisitable
    var action: TLAction
    var webView: TLWebView
    var state: TLVisitState

    var location: NSURL
    var hasCachedSnapshot: Bool = false
    var restorationIdentifier: String?

    override var description: String {
        return "<\(self.dynamicType): state=\(state.rawValue) location=\(location)>"
    }

    init(visitable: TLVisitable, action: TLAction, webView: TLWebView) {
        self.visitable = visitable
        self.location = visitable.location!
        self.action = action
        self.webView = webView
        self.state = .Initialized
    }

    func start() {
        if state == .Initialized {
            delegate?.visitWillStart(self)
            state = .Started
            startVisit()
        }
    }

    func cancel() {
        if state == .Started {
            state = .Canceled
            cancelVisit()
        }
    }

    private func complete() {
        if state == .Started {
            state = .Completed
            delegate?.visitDidComplete(self)
        }
    }

    private func fail(callback: (() -> Void)? = nil) {
        if state == .Started {
            state = .Failed
            callback?()
            failVisit()
            delegate?.visitDidFail(self)
        }
    }

    private func startVisit() {}
    private func cancelVisit() {}
    private func failVisit() {}

    // MARK: Navigation

    private var navigationCompleted = false
    private var navigationCallback: (() -> Void)?

    func completeNavigation() {
        if state == .Started && !navigationCompleted {
            navigationCompleted = true
            navigationCallback?()
        }
    }

    private func afterNavigationCompletion(callback: () -> Void) {
        if navigationCompleted {
            callback()
        } else {
            let previousNavigationCallback = navigationCallback
            navigationCallback = { [unowned self] in
                previousNavigationCallback?()
                if self.state != .Canceled {
                    callback()
                }
            }
        }
    }


    // MARK: Request state

    private var requestStarted = false
    private var requestFinished = false

    private func startRequest() {
        if !requestStarted {
            requestStarted = true
            delegate?.visitRequestDidStart(self)
        }
    }

    private func finishRequest() {
        if requestStarted && !requestFinished {
            requestFinished = true
            delegate?.visitRequestDidFinish(self)
        }
    }
}

class TLColdBootVisit: TLVisit, WKNavigationDelegate, TLWebViewPageLoadDelegate {
    private var navigation: WKNavigation?

    override private func startVisit() {
        webView.navigationDelegate = self
        webView.pageLoadDelegate = self

        let request = NSURLRequest(URL: location)
        navigation = webView.loadRequest(request)

        delegate?.visitDidStart(self)
        startRequest()
    }

    override private func cancelVisit() {
        webView.navigationDelegate = nil
        webView.stopLoading()
        finishRequest()
    }

    override private func failVisit() {
        webView.navigationDelegate = nil
        finishRequest()
    }

    // MARK: WKNavigationDelegate

    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        if navigation === self.navigation {
            webView.navigationDelegate = nil
            delegate?.visitDidInitializeWebView(self)
            finishRequest()
        }
    }
    
    func webView(webView: WKWebView, decidePolicyForNavigationAction navigationAction: WKNavigationAction, decisionHandler: (WKNavigationActionPolicy) -> Void) {
        // Ignore any clicked links before the cold boot finishes navigation
        if navigationAction.navigationType == .LinkActivated {
            decisionHandler(.Cancel)
            if let URL = navigationAction.request.URL {
                UIApplication.sharedApplication().openURL(URL)
            }
        } else {
            decisionHandler(.Allow)
        }
    }

    func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? NSHTTPURLResponse {
            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                decisionHandler(.Allow)
            } else {
                decisionHandler(.Cancel)
                fail {
                    let error = TLError(code: .HTTPFailure, statusCode: httpResponse.statusCode)
                    self.delegate?.visit(self, requestDidFailWithError: error)
                }
            }
        } else {
            decisionHandler(.Cancel)
            fail {
                let error = TLError(code: .NetworkFailure, localizedDescription: "An unknown error occurred")
                self.delegate?.visit(self, requestDidFailWithError: error)
            }
        }
    }

    func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError originalError: NSError) {
        if navigation === self.navigation {
            fail {
                let error = TLError(code: .NetworkFailure, error: originalError)
                self.delegate?.visit(self, requestDidFailWithError: error)
            }
        }
    }

    func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError originalError: NSError) {
        if navigation === self.navigation {
            fail {
                let error = TLError(code: .NetworkFailure, error: originalError)
                self.delegate?.visit(self, requestDidFailWithError: error)
            }
        }
    }

    // MARK: TLWebViewPageLoadDelegate

    func webView(webView: TLWebView, didLoadPageWithRestorationIdentifier restorationIdentifier: String) {
        self.restorationIdentifier = restorationIdentifier
        delegate?.visitDidRender(self)
        complete()
    }
}

class TLJavaScriptVisit: TLVisit, TLWebViewVisitDelegate {
    private var identifier = "(pending)"

    override var description: String {
        return "<\(self.dynamicType) \(identifier): state=\(state.rawValue) location=\(location)>"
    }

    override private func startVisit() {
        webView.visitDelegate = self
        webView.visitLocation(location, withAction: action, restorationIdentifier: restorationIdentifier)
    }

    override private func cancelVisit() {
        webView.cancelVisitWithIdentifier(identifier)
        finishRequest()
    }

    override private func failVisit() {
        finishRequest()
    }

    // MARK: TLWebViewVisitDelegate

    func webView(webView: TLWebView, didStartVisitWithIdentifier identifier: String, hasCachedSnapshot: Bool) {
        self.identifier = identifier
        self.hasCachedSnapshot = hasCachedSnapshot

        delegate?.visitDidStart(self)
        webView.issueRequestForVisitWithIdentifier(identifier)

        afterNavigationCompletion { [unowned self] in
            self.webView.changeHistoryForVisitWithIdentifier(identifier)
            self.webView.loadCachedSnapshotForVisitWithIdentifier(identifier)
        }
    }

    func webView(webView: TLWebView, didStartRequestForVisitWithIdentifier identifier: String) {
        if identifier == self.identifier {
            startRequest()
        }
    }

    func webView(webView: TLWebView, didCompleteRequestForVisitWithIdentifier identifier: String) {
        if identifier == self.identifier {
            afterNavigationCompletion { [unowned self] in
                self.delegate?.visitWillLoadResponse(self)
                self.webView.loadResponseForVisitWithIdentifier(identifier)
            }
        }
    }

    func webView(webView: TLWebView, didFailRequestForVisitWithIdentifier identifier: String, statusCode: Int) {
        if identifier == self.identifier {
            fail {
                let error: NSError
                if statusCode == 0 {
                    error = TLError(code: .NetworkFailure, localizedDescription: "A network error occurred.")
                } else {
                    error = TLError(code: .HTTPFailure, statusCode: statusCode)
                }
                self.delegate?.visit(self, requestDidFailWithError: error)
            }
        }
    }

    func webView(webView: TLWebView, didFinishRequestForVisitWithIdentifier identifier: String) {
        if identifier == self.identifier {
            finishRequest()
        }
    }

    func webView(webView: TLWebView, didRenderForVisitWithIdentifier identifier: String) {
        if identifier == self.identifier {
            delegate?.visitDidRender(self)
        }
    }

    func webView(webView: TLWebView, didCompleteVisitWithIdentifier identifier: String, restorationIdentifier: String) {
        if identifier == self.identifier {
            self.restorationIdentifier = restorationIdentifier
            complete()
        }
    }
}