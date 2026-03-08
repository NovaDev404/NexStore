NAME := NexStore
PLATFORM := iphoneos
SCHEMES := NexStore
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
CERT_JSON_URL := https://backloop.dev/pack.json
WORKSPACE := NexStore.xcworkspace
SOURCE_PACKAGES := $(TMP)/SourcePackages

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
