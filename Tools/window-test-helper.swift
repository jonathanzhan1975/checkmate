// Test-host window preparation and observations. User interactions still use real pointer events.
import AppKit
import ApplicationServices

let pid=Int32(CommandLine.arguments[1])!,action=CommandLine.arguments[2]
let app=AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app,0.2)
func get(_ element:AXUIElement,_ key:String)->CFTypeRef? {var value:CFTypeRef?;AXUIElementCopyAttributeValue(element,key as CFString,&value);return value}
func fail(_ message:String)->Never {fputs(message+"\n",stderr);exit(1)}
guard let windows=get(app,kAXWindowsAttribute) as? [AXUIElement],let window=windows.first(where:{get($0,kAXIdentifierAttribute) as? String == "main"}) ?? (windows.count==1 ? windows.first:nil) else{fail("Main window unavailable")}
func bounds()->CGRect {
    guard let p=get(window,kAXPositionAttribute),let s=get(window,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{fail("Window geometry unavailable")}
    var point=CGPoint.zero,size=CGSize.zero
    guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else{fail("Window geometry invalid")}
    return CGRect(origin:point,size:size)
}
guard let screen=NSScreen.screens.first else{fail("Screen unavailable")}
let visible=screen.visibleFrame,full=screen.frame
let display=CGRect(x:visible.minX,y:full.maxY-visible.maxY,width:visible.width,height:visible.height)
switch action {
case "activate":NSRunningApplication(processIdentifier:pid)?.activate(options:[.activateAllWindows])
case "center":
    NSRunningApplication(processIdentifier:pid)?.activate(options:[.activateAllWindows])
    let frame=bounds()
    guard frame.width<=display.width,frame.height<=display.height else{fail("Window cannot fit on test display: \(frame) in \(display)")}
    var point=CGPoint(x:display.midX-frame.width/2,y:display.midY-frame.height/2)
    guard let value=AXValueCreate(.cgPoint,&point),AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,value) == .success else{fail("Cannot position test window")}
case "geometry":let frame=bounds();print("\(frame.minX) \(frame.minY) \(frame.width) \(frame.height)")
case "on-screen":print(display.insetBy(dx:-1,dy:-1).contains(bounds()))
case "fullscreen":
    let desired=CommandLine.arguments[3]=="on"
    NSRunningApplication(processIdentifier:pid)?.activate(options:[.activateAllWindows])
    if (get(window,"AXFullScreen") as? Bool) != desired {
        guard AXUIElementSetAttributeValue(window,"AXFullScreen" as CFString,desired ? kCFBooleanTrue:kCFBooleanFalse) == .success else{fail("Fullscreen transition not ready")}
    }
case "fullscreen-state":
    guard let current=get(window,"AXFullScreen") as? Bool else{fail("Fullscreen state unavailable")}
    print(current ? "full":"normal")
case "diagnostic":print("windows=\(windows.count) fullScreen=\(String(describing:get(window,"AXFullScreen"))) frame=\(bounds()) screen=\(full) visible=\(display)")
default:fail("Unknown action")
}
