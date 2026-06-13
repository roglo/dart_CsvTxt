all:
	flutter run --release

linux:
	GDK_SCALE=2 flutter run --release -d linux

clean:
	rm -rf build .dart_tool android/.gradle android/app/src/main/java
	rm -rf android/.kotlin
	rm -f pubspec.lock .flutter-plugins-dependencies android/gradlew.bat
	rm -f android/local.properties

.PHONY: all linux clean
