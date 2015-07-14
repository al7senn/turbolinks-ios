import UIKit
import WebKit
import Turbolinks

class WebViewController: UIViewController, Visitable {
    weak var visitableDelegate: VisitableDelegate?
    var location: NSURL?
    var webView: WKWebView?
    var viewController: UIViewController { return self }

    override func viewDidLoad() {
        super.viewDidLoad()

        edgesForExtendedLayout = .None
        automaticallyAdjustsScrollViewInsets = false

        view.backgroundColor = UIColor.whiteColor()
        
        insertActivityIndicator()
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        visitableDelegate?.visitableViewWillDisappear(self)
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        visitableDelegate?.visitableViewDidDisappear(self)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        visitableDelegate?.visitableViewWillAppear(self)
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        visitableDelegate?.visitableViewDidAppear(self)
    }

    // MARK: Web View

    func activateWebView(webView: WKWebView) {
        self.webView = webView
        view.addSubview(webView)
        view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|[view]|", options: nil, metrics: nil, views: [ "view": webView ]))
        view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|[view]|", options: nil, metrics: nil, views: [ "view": webView ]))
        view.sendSubviewToBack(webView)
    }

    func deactivateWebView() {
        webView = nil
    }

    // MARK: Activity Indicator

    lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .WhiteLarge)
        activityIndicator.setTranslatesAutoresizingMaskIntoConstraints(false)
        activityIndicator.color = UIColor.grayColor()
        return activityIndicator
    }()
    
    func showActivityIndicator() {
        activityIndicator.startAnimating()
        view.bringSubviewToFront(activityIndicator)
    }

    func hideActivityIndicator() {
        activityIndicator.stopAnimating()
    }

    private func insertActivityIndicator() {
        view.addSubview(activityIndicator)
        view.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .CenterX, relatedBy: .Equal, toItem: view, attribute: .CenterX, multiplier: 1, constant: 0))
        view.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .CenterY, relatedBy: .Equal, toItem: view, attribute: .CenterY, multiplier: 1, constant: 0))
    }
   
    // MARK: Screenshots

    private lazy var screenshotView: UIView = {
        let screenshotView = UIView(frame: CGRectZero)
        screenshotView.setTranslatesAutoresizingMaskIntoConstraints(false)
        screenshotView.backgroundColor = UIColor.whiteColor()
        return screenshotView
    }()
    
    private var screenshotVisible: Bool {
        return self.screenshotView.superview == self.view
    }

    func updateScreenshot() {
        if !screenshotVisible {
            self.screenshotView = view.snapshotViewAfterScreenUpdates(false)
        }
    }

    func showScreenshot() {
        if !screenshotVisible {
            let borderView = UIView(frame: CGRectMake(0, 0, view.frame.width, 5))
            borderView.backgroundColor = UIColor.greenColor()
            screenshotView.addSubview(borderView)

            view.addSubview(screenshotView)
            view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|[view]|", options: nil, metrics: nil, views: [ "view": screenshotView ]))
            view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|[view]|", options: nil, metrics: nil, views: [ "view": screenshotView ]))
        }
    }

    func hideScreenshot() {
        screenshotView.removeFromSuperview()
    }
}