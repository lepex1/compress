import 'dart:ffi';
import 'package:ffi/ffi.dart';

final DynamicLibrary _dwmapi = DynamicLibrary.open('dwmapi.dll');

final int Function(Pointer<Uint32>, Pointer<Int32>) _getColorizationColor =
    _dwmapi.lookupFunction<
        Int32 Function(Pointer<Uint32>, Pointer<Int32>),
        int Function(Pointer<Uint32>, Pointer<Int32>)>(
    'DwmGetColorizationColor');

int getWindowsAccentColor() {
  final colorPtr = calloc<Uint32>();
  final opaquePtr = calloc<Int32>();
  try {
    _getColorizationColor(colorPtr, opaquePtr);
    final argb = colorPtr.value;
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    if (a == 0) return 0xFF6750A4;
    return (a << 24) | (r << 16) | (g << 8) | b;
  } finally {
    calloc.free(colorPtr);
    calloc.free(opaquePtr);
  }
}
