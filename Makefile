NAME := NexStore
PLATFORM := iphoneos
SCHEMES := NexStore
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
CERT_JSON_URL := https://backloop.dev/pack.json
WORKSPACE := NexStore.xcworkspace
SOURCE_PACKAGES := $(TMP)/SourcePackages
OPENSSL_XCFRAMEWORK := $(SOURCE_PACKAGES)/artifacts/openssl-package/OpenSSL/OpenSSL.xcframework

.PHONY: all deps clean prepare_packages repair_openssl_artifact $(SCHEMES)

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

	# Xcode 26 rejects the shipped OpenSSL artifact signature, so resolve first,
	# repair the xcframework in-place, then build without re-resolving packages.
	xcodebuild \
	    -resolvePackageDependencies \
	    -workspace $(WORKSPACE) \
	    -scheme "$(firstword $(SCHEMES))" \
	    -clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	    -skipPackagePluginValidation || test -d "$(OPENSSL_XCFRAMEWORK)"

	$(MAKE) repair_openssl_artifact

repair_openssl_artifact:
	@if [ -d "$(OPENSSL_XCFRAMEWORK)" ]; then \
		echo "Re-signing $(OPENSSL_XCFRAMEWORK)"; \
		xattr -cr "$(OPENSSL_XCFRAMEWORK)" || true; \
		codesign --remove-signature "$(OPENSSL_XCFRAMEWORK)" 2>/dev/null || true; \
		codesign --force --deep --sign - --timestamp=none "$(OPENSSL_XCFRAMEWORK)"; \
		codesign --verify --deep --strict "$(OPENSSL_XCFRAMEWORK)"; \
	else \
		echo "OpenSSL.xcframework artifact not found, skipping signature repair."; \
	fi

$(SCHEMES): prepare_packages
	xcodebuild \
	    -workspace $(WORKSPACE) \
	    -scheme "$@" \
	    -configuration Release \
	    -arch arm64 \
	    -sdk $(PLATFORM) \
	    -derivedDataPath $(TMP) \
	    -clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	    -disableAutomaticPackageResolution \
	    -skipPackagePluginValidation \
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
