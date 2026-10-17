// Copyright (C) 2025 Potix Corporation. All Rights Reserved
// History: 2025/4/2 3:52 PM
// Author: jumperchen<jumperchen@potix.com>
bool isString(Object obj) {
  // Keep the runtime check platform-consistent on web/wasm. The JS interop
  // String type is not reliable for broad `Object` checks across targets.
  return obj is String;
}
