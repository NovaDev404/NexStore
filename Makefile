NAME := NexStore
PLATFORM := iphoneos
SCHEMES := NexStore
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
CERT_JSON_URL := https://backloop.dev/pack.json
WORKSPACE := NexStore.xcworkspace
SOURCE_PACKAGES := $(TMP)/SourcePackages
XCODEBUILD_OVERRIDES :=

ifdef BUILD_NUMBER
XCODEBUILD_OVERRIDES += CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)
endif

.PHONY: all deps clean prepare_packages $(SCHEMES)

all: $(SCHEMES)

clean:
	rm -rf $(TMP)
	rm -rf packages
	rm -rf Payload

deps:
	rm -rf deps || true
	mkdir -p deps

	# Ensure local Swift package submodules (e.g. Zsign, IDeviceKitten) exist before package resolution.
	git submodule update --init --recursive

	curl -fsSL "$(CERT_JSON_URL)" -o cert.json

	jq -r '.cert' cert.json > deps/server.crt
	jq -r '.key1, .key2' cert.json > deps/server.pem
	jq -r '.info.domains.commonName' cert.json > deps/commonName.txt

prepare_packages: deps
	mkdir -p "$(SOURCE_PACKAGES)"

	xcodebuild \
	    -resolvePackageDependencies \
	    -workspace $(WORKSPACE) \
	    -scheme "$(firstword $(SCHEMES))" \
	    -clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	    -skipPackagePluginValidation

	ALT_SIGN_OPENSSL_XCFRAMEWORK="$$(find "$(SOURCE_PACKAGES)/checkouts" -path "*/Dependencies/OpenSSL.xcframework" -type d | head -n 1)"; \
	if [ -z "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" ]; then \
		echo "Expected AltSign OpenSSL.xcframework after package resolution." >&2; \
		exit 1; \
	fi

$(SCHEMES): prepare_packages
	# Zsign expects <openssl/...> headers; reuse AltSign's vendored XCFramework to avoid a second OpenSSL copy.
	ALT_SIGN_OPENSSL_XCFRAMEWORK="$$(find "$(SOURCE_PACKAGES)/checkouts" -path "*/Dependencies/OpenSSL.xcframework" -type d | head -n 1)"; \
	if [ -z "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" ]; then \
		echo "Expected AltSign OpenSSL.xcframework after package resolution." >&2; \
		exit 1; \
	fi; \
	case "$(PLATFORM)" in \
		iphonesimulator) \
			OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/OpenSSL.framework" -type d | grep -i simulator | head -n 1)" ;; \
		*) \
			# Prefer an iOS device slice; avoid maccatalyst unless nothing else exists. \
			OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/ios-*/OpenSSL.framework" -type d | grep -vi simulator | grep -vi maccatalyst | head -n 1)"; \
			if [ -z "$$OPENSSL_FRAMEWORK" ]; then \
				OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/OpenSSL.framework" -type d | grep -vi maccatalyst | head -n 1)"; \
			fi; \
			if [ -z "$$OPENSSL_FRAMEWORK" ]; then \
				OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/OpenSSL.framework" -type d | head -n 1)"; \
			fi; \
		;; \
	esac; \
	if [ -z "$$OPENSSL_FRAMEWORK" ]; then \
		OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/OpenSSL.framework" -type d | head -n 1)"; \
	fi; \
	if [ -z "$$OPENSSL_FRAMEWORK" ]; then \
		echo "Unable to locate an OpenSSL.framework slice inside $$ALT_SIGN_OPENSSL_XCFRAMEWORK." >&2; \
		exit 1; \
	fi; \
	OPENSSL_HEADERS="$$OPENSSL_FRAMEWORK/Headers"; \
	OPENSSL_FRAMEWORK_DIR="$${OPENSSL_FRAMEWORK%/OpenSSL.framework}"; \
	CPATH="$$OPENSSL_HEADERS" CPLUS_INCLUDE_PATH="$$OPENSSL_HEADERS" OBJC_INCLUDE_PATH="$$OPENSSL_HEADERS" \
	xcodebuild $(XCODEBUILD_OVERRIDES) \
	    -workspace $(WORKSPACE) \
	    -scheme "$@" \
	    -configuration Release \
	    -arch arm64 \
	    -sdk $(PLATFORM) \
	    -derivedDataPath $(TMP) \
	    -clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	    -disableAutomaticPackageResolution \
	    -skipPackagePluginValidation \
	    HEADER_SEARCH_PATHS="$$OPENSSL_HEADERS" \
	    SYSTEM_HEADER_SEARCH_PATHS="$$OPENSSL_HEADERS" \
	    OTHER_CFLAGS="-I$$OPENSSL_HEADERS" \
	    OTHER_CPLUSPLUSFLAGS="-I$$OPENSSL_HEADERS" \
	    OTHER_LDFLAGS="-F$$OPENSSL_FRAMEWORK_DIR" \
	    CODE_SIGNING_ALLOWED=NO \
	    ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO

	rm -rf Payload
	rm -rf $(STAGE)/
	mkdir -p $(STAGE)/Payload

	mv "$(APP)/$@.app" "$(STAGE)/Payload/$@.app"

	chmod -R 0755 "$(STAGE)/Payload/$@.app"
	codesign --force --sign - --timestamp=none "$(STAGE)/Payload/$@.app"

	cp deps/* "$(STAGE)/Payload/$@.app/" || true

	rm -rf "$(STAGE)/Payload/$@.app/_CodeSignature"
	ln -sf "$(STAGE)/Payload" Payload
	
	mkdir -p packages
	zip -r9 "packages/$@.ipa" Payload
