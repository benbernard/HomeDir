#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <node_api.h>

// ─── Global state for async picker callback ───
static napi_threadsafe_function g_tsfn = NULL;
static napi_deferred g_deferred = NULL;

// ─── Picker observer ───

API_AVAILABLE(macos(15.0))
@interface MeetyPickerObserver : NSObject <SCContentSharingPickerObserver>
@end

@implementation MeetyPickerObserver

- (void)contentSharingPicker:(SCContentSharingPicker *)picker
         didUpdateWithFilter:(SCContentFilter *)filter
                   forStream:(SCStream *)stream {
  if (stream != nil) return;

  [picker removeObserver:self];
  picker.active = NO;

  CGRect filterRect = filter.contentRect;
  NSLog(@"[Meety Native] Picker selected content at rect: %@", NSStringFromRect(filterRect));

  // Match the selected content to a window by frame
  [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
    int64_t windowId = -1;
    if (!error) {
      for (SCWindow *window in content.windows) {
        if (CGRectEqualToRect(window.frame, filterRect)) {
          windowId = (int64_t)window.windowID;
          NSLog(@"[Meety Native] Matched window: %@ (id=%lld)", window.title, windowId);
          break;
        }
      }
      if (windowId < 0) {
        NSLog(@"[Meety Native] No window matched filterRect, trying closest match");
        // Fallback: find closest window by center point
        CGPoint filterCenter = CGPointMake(CGRectGetMidX(filterRect), CGRectGetMidY(filterRect));
        CGFloat bestDist = CGFLOAT_MAX;
        for (SCWindow *window in content.windows) {
          if (!window.isOnScreen) continue;
          CGPoint wCenter = CGPointMake(CGRectGetMidX(window.frame), CGRectGetMidY(window.frame));
          CGFloat dx = filterCenter.x - wCenter.x;
          CGFloat dy = filterCenter.y - wCenter.y;
          CGFloat dist = dx*dx + dy*dy;
          // Also check size similarity
          CGFloat sw = fabs(filterRect.size.width - window.frame.size.width);
          CGFloat sh = fabs(filterRect.size.height - window.frame.size.height);
          if (sw < 2 && sh < 2 && dist < bestDist) {
            bestDist = dist;
            windowId = (int64_t)window.windowID;
          }
        }
        if (windowId >= 0) {
          NSLog(@"[Meety Native] Closest match window id=%lld", windowId);
        }
      }
    } else {
      NSLog(@"[Meety Native] Error getting shareable content: %@", error);
    }

    if (g_tsfn) {
      int64_t *data = (int64_t *)malloc(sizeof(int64_t));
      *data = windowId;
      napi_call_threadsafe_function(g_tsfn, data, napi_tsfn_nonblocking);
      napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
      g_tsfn = NULL;
    }
  }];
}

- (void)contentSharingPicker:(SCContentSharingPicker *)picker
          didCancelForStream:(SCStream *)stream {
  NSLog(@"[Meety Native] Picker cancelled");
  [picker removeObserver:self];
  picker.active = NO;

  if (g_tsfn) {
    int64_t *data = (int64_t *)malloc(sizeof(int64_t));
    *data = -1;
    napi_call_threadsafe_function(g_tsfn, data, napi_tsfn_nonblocking);
    napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
    g_tsfn = NULL;
  }
}

- (void)contentSharingPickerStartDidFailWithError:(NSError *)error {
  NSLog(@"[Meety Native] Picker error: %@", error);

  // Clean up picker state — without this, macOS thinks sharing is still
  // active (menu bar indicator persists, audio routing stays in "sharing" mode).
  if (@available(macOS 15.0, *)) {
    SCContentSharingPicker *picker = [SCContentSharingPicker sharedPicker];
    [picker removeObserver:self];
    picker.active = NO;
  }

  if (g_tsfn) {
    int64_t *data = (int64_t *)malloc(sizeof(int64_t));
    *data = -1;
    napi_call_threadsafe_function(g_tsfn, data, napi_tsfn_nonblocking);
    napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
    g_tsfn = NULL;
  }
}

@end

// ─── JS callback bridge ───

static void CallJS(napi_env env, napi_value js_cb, void *context, void *data) {
  int64_t windowId = *(int64_t *)data;
  free(data);

  if (!g_deferred) return;

  napi_value result;
  if (windowId >= 0) {
    napi_create_int64(env, windowId, &result);
  } else {
    napi_get_null(env, &result);
  }
  napi_resolve_deferred(env, g_deferred, result);
  g_deferred = NULL;
}

// ─── Exported functions ───

// configurePicker() - initialize the system picker with default settings.
// Dispatches to the main thread — ScreenCaptureKit's shared singleton must
// only be accessed from the main thread to avoid corrupting internal state.
static napi_value ConfigurePicker(napi_env env, napi_callback_info info) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (@available(macOS 15.0, *)) {
      SCContentSharingPicker *picker = [SCContentSharingPicker sharedPicker];
      SCContentSharingPickerConfiguration *config = [[SCContentSharingPickerConfiguration alloc] init];
      config.allowedPickerModes = SCContentSharingPickerModeSingleWindow;
      picker.defaultConfiguration = config;
      NSLog(@"[Meety Native] Picker configured for single-window mode");
    }
  });
  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

// presentWindowPicker() -> Promise<number | null>
// Presents the native macOS system picker configured for window selection.
// Returns the CGWindowID of the selected window, or null if cancelled.
static napi_value PresentWindowPicker(napi_env env, napi_callback_info info) {
  napi_value promise;
  napi_create_promise(env, &g_deferred, &promise);

  if (@available(macOS 15.0, *)) {
    napi_value resource_name;
    napi_create_string_utf8(env, "picker_cb", NAPI_AUTO_LENGTH, &resource_name);
    napi_create_threadsafe_function(env, NULL, NULL, resource_name, 0, 1,
                                    NULL, NULL, NULL, CallJS, &g_tsfn);

    // All SCContentSharingPicker interaction must happen on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
      SCContentSharingPicker *picker = [SCContentSharingPicker sharedPicker];

      // Re-apply configuration before each present — the shared picker's
      // state may be cleared after the observer sets active = NO.
      SCContentSharingPickerConfiguration *config = [[SCContentSharingPickerConfiguration alloc] init];
      config.allowedPickerModes = SCContentSharingPickerModeSingleWindow;
      picker.defaultConfiguration = config;
      picker.maximumStreamCount = @1;

      static MeetyPickerObserver *observer = nil;
      observer = [[MeetyPickerObserver alloc] init];
      [picker addObserver:observer];
      picker.active = YES;
      [picker present];
      NSLog(@"[Meety Native] Presented window picker (single-window mode)");
    });
  } else {
    napi_value null_val;
    napi_get_null(env, &null_val);
    napi_resolve_deferred(env, g_deferred, null_val);
    g_deferred = NULL;
  }

  return promise;
}

// cleanupPicker() - deactivate the picker on app shutdown so macOS
// releases the sharing session (clears menu bar indicator, restores audio).
static napi_value CleanupPicker(napi_env env, napi_callback_info info) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (@available(macOS 15.0, *)) {
      SCContentSharingPicker *picker = [SCContentSharingPicker sharedPicker];
      picker.active = NO;
      NSLog(@"[Meety Native] Picker deactivated on cleanup");
    }
  });
  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

// ─── Module init ───

static napi_value Init(napi_env env, napi_value exports) {
  napi_value fn1, fn2, fn3;
  napi_create_function(env, "configurePicker", NAPI_AUTO_LENGTH, ConfigurePicker, NULL, &fn1);
  napi_create_function(env, "presentWindowPicker", NAPI_AUTO_LENGTH, PresentWindowPicker, NULL, &fn2);
  napi_create_function(env, "cleanupPicker", NAPI_AUTO_LENGTH, CleanupPicker, NULL, &fn3);
  napi_set_named_property(env, exports, "configurePicker", fn1);
  napi_set_named_property(env, exports, "presentWindowPicker", fn2);
  napi_set_named_property(env, exports, "cleanupPicker", fn3);
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
