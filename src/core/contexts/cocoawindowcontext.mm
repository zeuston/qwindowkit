#include "cocoawindowcontext_p.h"

#include <objc/runtime.h>
#include <AppKit/AppKit.h>

#include <QtGui/QGuiApplication>

namespace QWK {

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    static const struct QWK_Hook {
        QWK_Hook() {
            qputenv("QT_MAC_WANTS_LAYER", "1");
        }
    } g_hook{};
#endif

    struct NSWindowProxy {
        NSWindowProxy(NSWindow *macWindow) {
            if (instances.contains(macWindow)) {
                return;
            }
            nswindow = macWindow;
            instances.insert(macWindow, this);
            if (!windowClass) {
                windowClass = [nswindow class];
                replaceImplementations();
            }
        }

        ~NSWindowProxy() {
            instances.remove(nswindow);
            if (instances.count() <= 0) {
                restoreImplementations();
                windowClass = nil;
            }
            nswindow = nil;
        }

        void replaceImplementations() {
            Method method = class_getInstanceMethod(windowClass, @selector(setStyleMask:));
            oldSetStyleMask = reinterpret_cast<setStyleMaskPtr>(
                method_setImplementation(method, reinterpret_cast<IMP>(setStyleMask)));

            method =
                class_getInstanceMethod(windowClass, @selector(setTitlebarAppearsTransparent:));
            oldSetTitlebarAppearsTransparent =
                reinterpret_cast<setTitlebarAppearsTransparentPtr>(method_setImplementation(
                    method, reinterpret_cast<IMP>(setTitlebarAppearsTransparent)));

#if 0
            method = class_getInstanceMethod(windowClass, @selector(canBecomeKeyWindow));
            oldCanBecomeKeyWindow = reinterpret_cast<canBecomeKeyWindowPtr>(method_setImplementation(method, reinterpret_cast<IMP>(canBecomeKeyWindow)));

            method = class_getInstanceMethod(windowClass, @selector(canBecomeMainWindow));
            oldCanBecomeMainWindow = reinterpret_cast<canBecomeMainWindowPtr>(method_setImplementation(method, reinterpret_cast<IMP>(canBecomeMainWindow)));
#endif

            method = class_getInstanceMethod(windowClass, @selector(sendEvent:));
            oldSendEvent = reinterpret_cast<sendEventPtr>(
                method_setImplementation(method, reinterpret_cast<IMP>(sendEvent)));
        }

        void restoreImplementations() {
            Method method = class_getInstanceMethod(windowClass, @selector(setStyleMask:));
            method_setImplementation(method, reinterpret_cast<IMP>(oldSetStyleMask));
            oldSetStyleMask = nil;

            method =
                class_getInstanceMethod(windowClass, @selector(setTitlebarAppearsTransparent:));
            method_setImplementation(method,
                                     reinterpret_cast<IMP>(oldSetTitlebarAppearsTransparent));
            oldSetTitlebarAppearsTransparent = nil;

#if 0
            method = class_getInstanceMethod(windowClass, @selector(canBecomeKeyWindow));
            method_setImplementation(method, reinterpret_cast<IMP>(oldCanBecomeKeyWindow));
            oldCanBecomeKeyWindow = nil;

            method = class_getInstanceMethod(windowClass, @selector(canBecomeMainWindow));
            method_setImplementation(method, reinterpret_cast<IMP>(oldCanBecomeMainWindow));
            oldCanBecomeMainWindow = nil;
#endif

            method = class_getInstanceMethod(windowClass, @selector(sendEvent:));
            method_setImplementation(method, reinterpret_cast<IMP>(oldSendEvent));
            oldSendEvent = nil;
        }

        void setSystemTitleBarVisible(const bool visible) {
            NSView *nsview = [nswindow contentView];
            if (!nsview) {
                return;
            }
            nsview.wantsLayer = YES;
            nswindow.styleMask |= NSWindowStyleMaskResizable;
            if (visible) {
                nswindow.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
            } else {
                nswindow.styleMask |= NSWindowStyleMaskFullSizeContentView;
            }
            nswindow.titlebarAppearsTransparent = (visible ? NO : YES);
            nswindow.titleVisibility = (visible ? NSWindowTitleVisible : NSWindowTitleHidden);
            nswindow.hasShadow = YES;
            nswindow.showsToolbarButton = NO;
            nswindow.movableByWindowBackground = NO;
            //nswindow.movable = NO; // This line causes the window in the wrong position when become fullscreen.
            // For some unknown reason, we don't need the following hack in Qt versions below or
            // equal to 6.2.4.
#if (QT_VERSION > QT_VERSION_CHECK(6, 2, 4))
            [nswindow standardWindowButton:NSWindowCloseButton].hidden = (visible ? NO : YES);
            [nswindow standardWindowButton:NSWindowMiniaturizeButton].hidden = (visible ? NO : YES);
            [nswindow standardWindowButton:NSWindowZoomButton].hidden = (visible ? NO : YES);
#endif
        }

    private:
        static BOOL canBecomeKeyWindow(id obj, SEL sel) {
            if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
                return YES;
            }

            if (oldCanBecomeKeyWindow) {
                return oldCanBecomeKeyWindow(obj, sel);
            }

            return YES;
        }

        static BOOL canBecomeMainWindow(id obj, SEL sel) {
            if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
                return YES;
            }

            if (oldCanBecomeMainWindow) {
                return oldCanBecomeMainWindow(obj, sel);
            }

            return YES;
        }

        static void setStyleMask(id obj, SEL sel, NSWindowStyleMask styleMask) {
            if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
                styleMask |= NSWindowStyleMaskFullSizeContentView;
            }

            if (oldSetStyleMask) {
                oldSetStyleMask(obj, sel, styleMask);
            }
        }

        static void setTitlebarAppearsTransparent(id obj, SEL sel, BOOL transparent) {
            if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
                transparent = YES;
            }

            if (oldSetTitlebarAppearsTransparent) {
                oldSetTitlebarAppearsTransparent(obj, sel, transparent);
            }
        }

        static void sendEvent(id obj, SEL sel, NSEvent *event) {
            if (oldSendEvent) {
                oldSendEvent(obj, sel, event);
            }

#if 0
            const auto nswindow = reinterpret_cast<NSWindow *>(obj);
            const auto it = instances.find(nswindow);
            if (it == instances.end()) {
                return;
            }

            NSWindowProxy *proxy = it.value();
            if (event.type == NSEventTypeLeftMouseDown) {
                proxy->lastMouseDownEvent = event;
                QCoreApplication::processEvents();
                proxy->lastMouseDownEvent = nil;
            }
#endif
        }

    private:
        Q_DISABLE_COPY(NSWindowProxy)

        NSWindow *nswindow = nil;
        // NSEvent *lastMouseDownEvent = nil;

        static inline QHash<NSWindow *, NSWindowProxy *> instances = {};

        static inline Class windowClass = nil;

        using setStyleMaskPtr = void (*)(id, SEL, NSWindowStyleMask);
        static inline setStyleMaskPtr oldSetStyleMask = nil;

        using setTitlebarAppearsTransparentPtr = void (*)(id, SEL, BOOL);
        static inline setTitlebarAppearsTransparentPtr oldSetTitlebarAppearsTransparent = nil;

        using canBecomeKeyWindowPtr = BOOL (*)(id, SEL);
        static inline canBecomeKeyWindowPtr oldCanBecomeKeyWindow = nil;

        using canBecomeMainWindowPtr = BOOL (*)(id, SEL);
        static inline canBecomeMainWindowPtr oldCanBecomeMainWindow = nil;

        using sendEventPtr = void (*)(id, SEL, NSEvent *);
        static inline sendEventPtr oldSendEvent = nil;
    };

    using ProxyList = QHash<WId, NSWindowProxy *>;
    Q_GLOBAL_STATIC(ProxyList, g_proxyList);

    static inline NSWindow *mac_getNSWindow(const WId windowId) {
        const auto nsview = reinterpret_cast<NSView *>(windowId);
        return [nsview window];
    }

    static inline void cleanupProxy() {
        if (g_proxyList()->isEmpty()) {
            return;
        }
        const auto &data = *g_proxyList();
        qDeleteAll(data);
        g_proxyList()->clear();
    }

    static inline NSWindowProxy *ensureWindowProxy(const WId windowId) {
        auto it = g_proxyList()->find(windowId);
        if (it == g_proxyList()->end()) {
            NSWindow *nswindow = mac_getNSWindow(windowId);
            const auto proxy = new NSWindowProxy(nswindow);
            it = g_proxyList()->insert(windowId, proxy);
        }
        static bool cleanerInstalled = false;
        if (!cleanerInstalled) {
            cleanerInstalled = true;
            qAddPostRoutine(cleanupProxy);
        }
        return it.value();
    }

    CocoaWindowContext::CocoaWindowContext() {
    }

    CocoaWindowContext::~CocoaWindowContext() {
    }

    QString CocoaWindowContext::key() const {
        return QStringLiteral("cocoa");
    }

    void CocoaWindowContext::virtual_hook(int id, void *data) {
    }

    bool CocoaWindowContext::setupHost() {
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
        m_windowHandle->setProperty("_q_mac_wantsLayer", 1);
#endif
        WId winId = m_windowHandle->winId();
        ensureWindowProxy(winId)->setSystemTitleBarVisible(false);
        // Cache window ID
        windowId = winId;
        return true;
    }

}
