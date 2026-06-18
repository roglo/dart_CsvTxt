all:
	flutter run --release

compile:
	flutter build apk --release

linux:
	GDK_SCALE=2 flutter run --release -d linux

linux_run:
	GDK_SCALE=2 build/linux/x64/release/bundle/csvtxt

clean:
	rm -rf build .dart_tool android/.gradle android/app/src/main/java
	rm -rf android/.kotlin
	rm -f pubspec.lock .flutter-plugins-dependencies android/gradlew.bat
	rm -f android/local.properties
	rm -rf linux/flutter/ephemeral
	rm -f linux/flutter/generated_plugin_registrant.h
	rm -f linux/flutter/generated_plugin_registrant.cc
	rm -f linux/flutter/generated_plugins.cmake
	rm -f a.out lib/find_sep.cm[ix] lib/find_sep.o

analyze:
	flutter analyze

pretty:
	dart format lib/find_sep.dart
	dart format lib/picker.dart
	dart format lib/main.dart

copy_src:
	adb push lib/find_sep.ml /sdcard/Download/.
	adb push lib/find_sep.dart /sdcard/Download/.
	adb push lib/picker.dart /sdcard/Download/.
	adb push lib/main.dart /sdcard/Download/.

find_sep:
	ocamlopt -pp camlp5r lib/find_sep.ml

clean_adb:
	adb kill-server
	adb start-server
	adb devices

.PHONY: all compile linux clean analyze pretty copy_src find_sep clear_adb
