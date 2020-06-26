#include "AppMac.h"
#include <Ultralight/platform/Platform.h>
#include <Ultralight/platform/Config.h>
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "WindowMac.h"
#import "metal/GPUContextMetal.h"
#import "metal/GPUDriverMetal.h"
#include <AppCore/Platform.h>
#include "ClipboardMac.h"
#include <vector>
#include <CoreFoundation/CFString.h>
#include <iostream>
#include <Ultralight/private/util/Debug.h>
#include <Ultralight/private/PlatformFileSystem.h>

@interface UpdateTimer : NSObject
@property NSTimer *timer;
- (id)init;
- (void)onTick:(NSTimer *)aTimer;
@end

// Run update timer at 120 FPS
@implementation UpdateTimer
- (id)init {
  id newInstance = [super init];
  if (newInstance) {
    _timer = [NSTimer scheduledTimerWithTimeInterval:(1.0/120.0)
                                              target:self
                                            selector:@selector(onTick:)
                                            userInfo:nil
                                             repeats:YES];
  }
  
  return newInstance;
}

-(void)onTick:(NSTimer *)aTimer {
  static_cast<ultralight::AppMac*>(ultralight::App::instance())->Update();
}
@end

namespace ultralight {

static String16 ToString16(CFStringRef str) {
    if (!str)
        return String16();
    CFIndex size = CFStringGetLength(str);
    std::vector<Char16> buffer(size);
    CFStringGetCharacters(str, CFRangeMake(0, size), (UniChar*)buffer.data());
    return String16(buffer.data(), size);
}

static String16 GetSystemCachePath() {
  NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString* cacheDir = [paths objectAtIndex:0];
  return ToString16((__bridge CFStringRef)cacheDir);
}

static String16 GetBundleResourcePath() {
  return ToString16((__bridge CFStringRef)[[NSBundle mainBundle] resourcePath]);
}

AppMac::AppMac(Settings settings, Config config) : settings_(settings) {
  [NSApplication sharedApplication];
  
  AppDelegate *appDelegate = [[AppDelegate alloc] init];
  [NSApp setDelegate:appDelegate];

  // Force GPU renderer by default until we support CPU drawing in this port
  config.use_gpu_renderer = true;

  // Generate cache path
  String cache_path = GetSystemCachePath();
  String cache_dirname = "com." + settings_.developer_name + "." +
    settings_.app_name;
  cache_path = PlatformFileSystem::AppendPath(cache_path, cache_dirname);
  PlatformFileSystem::MakeAllDirectories(cache_path);

  String log_path = PlatformFileSystem::AppendPath(cache_path,
                                                   "ultralight.log");
  
  logger_.reset(new FileLogger(log_path));
  Platform::instance().set_logger(logger_.get());

  // Determine resources path
  String bundle_resource_path = GetBundleResourcePath();
  String resource_path = PlatformFileSystem::AppendPath(bundle_resource_path, "resources/");

  config.cache_path = cache_path.utf16();
  config.resource_path = resource_path.utf16();
  config.device_scale = main_monitor_.scale();
  config.face_winding = kFaceWinding_Clockwise;
  Platform::instance().set_config(config);

  // Determine file system path
  String file_system_path = PlatformFileSystem::AppendPath(bundle_resource_path, settings_.file_system_path.utf16());

  Platform::instance().set_file_system(GetPlatformFileSystem(file_system_path));
  
  std::ostringstream info;
  info << "File system base directory resolved to: " <<
    file_system_path.utf8().data();
  UL_LOG_INFO(info.str().c_str());

  Platform::instance().set_font_loader(GetPlatformFontLoader());
  
  clipboard_.reset(new ClipboardMac());
  Platform::instance().set_clipboard(clipboard_.get());

  renderer_ = Renderer::Create();
}

AppMac::~AppMac() {
}

void AppMac::OnClose() {
}

void AppMac::OnResize(uint32_t width, uint32_t height) {
  if (gpu_context_) {
    gpu_context_->Resize((int)width, (int)height);
  }
}

void AppMac::set_window(Ref<Window> window) {
  window_ = window;
    
  WindowMac* win = static_cast<WindowMac*>(window_.get());
    
  gpu_context_.reset(new GPUContextMetal(win->layer().device, win->width(),
                                         win->height(), win->scale(),
                                         win->is_fullscreen(), true, true));
  Platform::instance().set_gpu_driver(gpu_context_->driver());
  win->set_app_listener(this);
}

Monitor* AppMac::main_monitor() {
  return &main_monitor_;
}

Ref<Renderer> AppMac::renderer() {
  return *renderer_.get();
}

void AppMac::Run() {
  if (!window_) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Forgot to call App::set_window before App::Run"];
    [alert runModal];
    exit(-1);
  }

  if (is_running_)
    return;

  is_running_ = true;
  UpdateTimer* timer = [[UpdateTimer alloc] init];
  [NSApp run];
  is_running_ = false;
}

void AppMac::Quit() {
  [NSApp terminate:nil];
}

void AppMac::Update() {
  if (listener_)
    listener_->OnUpdate();

  renderer()->Update();
  if(window() && static_cast<WindowMac*>(window_.get())->NeedsRepaint())
      static_cast<WindowMac*>(window_.get())->SetNeedsDisplay();
}
    
void AppMac::OnPaint(CAMetalLayer* layer) {
  if (!gpu_context_)
    return;

  if (listener_)
    listener_->OnUpdate();

  renderer()->Update();

  if (!static_cast<WindowMac*>(window_.get())->NeedsRepaint())
    return;
  
  gpu_context_->set_current_drawable([layer nextDrawable]);

  gpu_context_->driver()->BeginSynchronize();
  renderer_->Render();
  gpu_context_->driver()->EndSynchronize();

  if (gpu_context_->driver()->HasCommandsPending()) {
    gpu_context_->BeginDrawing();
    gpu_context_->driver()->DrawCommandList();
    if (window_)
      static_cast<WindowMac*>(window_.get())->Draw();
    gpu_context_->EndDrawing();
    gpu_context_->PresentFrame();
  }
}

static App* g_app_instance = nullptr;

Ref<App> App::Create(Settings settings, Config config) {
  g_app_instance = (App*)new AppMac(settings, config);
  return AdoptRef(*g_app_instance);
}

App::~App() {
  g_app_instance = nullptr;
}

App* App::instance() {
  return g_app_instance;
}

}  // namespace ultralight
