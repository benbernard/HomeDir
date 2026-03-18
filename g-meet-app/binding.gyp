{
  "targets": [
    {
      "target_name": "picker_config",
      "sources": ["native/picker_config.mm"],
      "cflags!": ["-std=gnu++20"],
      "conditions": [
        ["OS=='mac'", {
          "xcode_settings": {
            "GCC_ENABLE_OBJC_ARC": "YES",
            "OTHER_CPLUSPLUSFLAGS!": ["-std=gnu++20"],
            "OTHER_CFLAGS": ["-x", "objective-c++", "-std=gnu++20"],
            "OTHER_LDFLAGS": ["-framework", "ScreenCaptureKit", "-framework", "Foundation", "-framework", "CoreGraphics"]
          }
        }]
      ]
    }
  ]
}
