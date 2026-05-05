#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

CAP_PLUGIN(RichSharePlugin, "RichShare",
    CAP_PLUGIN_METHOD(share, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(saveImage, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(checkPermissions, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(requestPermissions, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(shareToInstagramStory, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(shareToTikTok, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(isAppInstalled, CAPPluginReturnPromise);
)
