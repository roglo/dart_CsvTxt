all:
	flutter run --release

compile:
	flutter build apk --release

linux:
	GDK_SCALE=2 flutter run --release -d linux

clean:
	rm -rf build .dart_tool android/.gradle android/app/src/main/java
	rm -rf android/.kotlin
	rm -f pubspec.lock .flutter-plugins-dependencies android/gradlew.bat
	rm -f android/local.properties
	rm -rf linux/flutter/ephemeral
	rm -f linux/flutter/generated_plugin_registrant.h
	rm -f linux/flutter/generated_plugin_registrant.cc
	rm -f linux/flutter/generated_plugins.cmake

.PHONY: all compile linux clean
