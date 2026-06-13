all:
	flutter run --release

linux:
	GDK_SCALE=2 flutter run --release -d linux

.PHONY: all linux
