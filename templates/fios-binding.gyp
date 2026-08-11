{
  "targets": [
    {
      "target_name": "fios",
      "sources": [
        "src/addon.cpp",
        "src/libfios-serial.c",
        "src/libfios-file.c",
        "src/libfios-export.c"
      ],
      "include_dirs": [
        "src",
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "dependencies": [
        "<!(node -p \"require('node-addon-api').gyp\")"
      ],
      "cflags_cc": ["-std=c++17", "-fexceptions"],
      "cflags_c": ["-std=gnu11"],
      "cflags_cc!": ["-fno-exceptions"],
      "cflags!": ["-fno-exceptions"]
    }
  ]
}
