.PHONY: build clean

build:
	clang -shared \
		-framework Foundation \
		-framework StoreKit \
		-framework UIKit \
		-o MNMaxUnlock.dylib \
		src/MNMaxUnlock.mm \
		-arch arm64 \
		-isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) \
		-miphoneos-version-min=15.0 \
		-fobjc-arc

clean:
	rm -f MNMaxUnlock.dylib
