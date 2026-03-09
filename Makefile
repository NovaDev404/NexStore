NAME := NexStore
PLATFORM := iphoneos
SCHEMES := NexStore
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
CERT_JSON_URL := https://backloop.dev/pack.json
WORKSPACE := NexStore.xcworkspace
SOURCE_PACKAGES := $(TMP)/SourcePackages
ALT_SIGN_PATH := AltSign
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

	ALT_SIGN_CHECKOUT="$(ALT_SIGN_PATH)"; \
	if [ -f "$$ALT_SIGN_CHECKOUT/.gitmodules" ]; then \
		git -C "$$ALT_SIGN_CHECKOUT" submodule sync --recursive; \
		git -C "$$ALT_SIGN_CHECKOUT" submodule update --init --recursive; \
	fi; \
	ALT_SIGN_LIBPLIST_SRC_DIR="$$ALT_SIGN_CHECKOUT/Dependencies/ldid/libplist/src"; \
	ALT_SIGN_LIBCNARY_INCLUDE_DIR="$$ALT_SIGN_CHECKOUT/Dependencies/ldid/libplist/libcnary/include"; \
	ALT_SIGN_LIBCNARY_NESTED_INCLUDE_DIR="$$ALT_SIGN_LIBCNARY_INCLUDE_DIR/cnary"; \
	ALT_SIGN_LIBPLIST_INCLUDE_DIR="$$ALT_SIGN_CHECKOUT/Dependencies/ldid/libplist/include/plist"; \
	ALT_SIGN_OPENSSL_XCFRAMEWORK="$$(find "$(ALT_SIGN_PATH)" "$(SOURCE_PACKAGES)" \( -path "*/Dependencies/OpenSSL.xcframework" -o -path "*/OpenSSL.xcframework" \) -type d 2>/dev/null | head -n 1)"; \
	if [ -z "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" ]; then \
		echo "Expected AltSign OpenSSL.xcframework after package resolution." >&2; \
		exit 1; \
	fi; \
	if [ -d "$$ALT_SIGN_LIBPLIST_SRC_DIR" ]; then \
		ALT_SIGN_LIBCNARY_HEADER_BASE="$$ALT_SIGN_LIBCNARY_INCLUDE_DIR"; \
		if [ ! -f "$$ALT_SIGN_LIBCNARY_HEADER_BASE/node.h" ] && [ -f "$$ALT_SIGN_LIBCNARY_NESTED_INCLUDE_DIR/node.h" ]; then \
			ALT_SIGN_LIBCNARY_HEADER_BASE="$$ALT_SIGN_LIBCNARY_NESTED_INCLUDE_DIR"; \
		fi; \
		if [ ! -f "$$ALT_SIGN_LIBCNARY_HEADER_BASE/node.h" ] || [ ! -f "$$ALT_SIGN_LIBCNARY_HEADER_BASE/object.h" ] || [ ! -f "$$ALT_SIGN_LIBCNARY_HEADER_BASE/node_list.h" ]; then \
			echo "Expected AltSign libcnary headers after submodule initialization." >&2; \
			exit 1; \
		fi; \
		for header in node.h object.h node_list.h; do \
			cp -f "$$ALT_SIGN_LIBCNARY_HEADER_BASE/$$header" "$$ALT_SIGN_LIBCNARY_INCLUDE_DIR/$$header"; \
			ln -sf ../libcnary/include/$$header "$$ALT_SIGN_LIBPLIST_SRC_DIR/$$header"; \
		done; \
		if [ -d "$$ALT_SIGN_LIBPLIST_INCLUDE_DIR" ]; then \
			find "$$ALT_SIGN_LIBPLIST_INCLUDE_DIR" -name '*.h' -exec perl -0pi -e 's/\b([A-Za-z_][A-Za-z0-9_]*)&\s+operator=\(((?:const\s+)?)(?:PList::)?\1&\s+([A-Za-z_][A-Za-z0-9_]*)\)/$$1\& operator=(const $$1\& $$3)/g' {} +; \
		fi; \
		find "$$ALT_SIGN_LIBPLIST_SRC_DIR" -name '*.cpp' -exec perl -0pi -e 's/\b([A-Za-z_][A-Za-z0-9_]*)&\s+\1::operator=\(((?:const\s+)?)(?:PList::)?\1&\s+([A-Za-z_][A-Za-z0-9_]*)\)/$$1\& $$1::operator=(const $$1\& $$3)/g' {} +; \
		ALT_SIGN_DICTIONARY_H="$$ALT_SIGN_LIBPLIST_INCLUDE_DIR/Dictionary.h"; \
		if [ -f "$$ALT_SIGN_DICTIONARY_H" ]; then \
			perl -0pi -e 's/\biterator\s+Insert\s*\(\s*(?:const\s+)?std::string\s*&\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(?:const\s+)?(?:PList::)?Node\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/iterator Insert(const std::string\& $$1, const Node* $$2)/g; s/\biterator\s+Insert\s*\(\s*(?:const\s+)?std::string\s*&\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(?:const\s+)?(?:PList::)?Node\s*&\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/iterator Insert(const std::string\& $$1, const Node\& $$2)/g' "$$ALT_SIGN_DICTIONARY_H"; \
		fi; \
		ALT_SIGN_DICTIONARY_CPP="$$ALT_SIGN_LIBPLIST_SRC_DIR/Dictionary.cpp"; \
		if [ -f "$$ALT_SIGN_DICTIONARY_CPP" ]; then \
			perl -0pi -e 's/\bDictionary::iterator\s+Dictionary::Insert\s*\(\s*(?:const\s+)?std::string\s*&\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(?:const\s+)?(?:PList::)?Node\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/Dictionary::iterator Dictionary::Insert(const std::string\& $$1, const Node* $$2)/g; s/\bDictionary::iterator\s+Dictionary::Insert\s*\(\s*(?:const\s+)?std::string\s*&\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(?:const\s+)?(?:PList::)?Node\s*&\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/Dictionary::iterator Dictionary::Insert(const std::string\& $$1, const Node\& $$2)/g' "$$ALT_SIGN_DICTIONARY_CPP"; \
		fi; \
		ALT_SIGN_INTEGER_CPP="$$ALT_SIGN_LIBPLIST_SRC_DIR/Integer.cpp"; \
		if [ -f "$$ALT_SIGN_INTEGER_CPP" ]; then \
			perl -0pi -e 's/\buint64_t\s+Integer::GetValue\(\)\s+const\b/int64_t Integer::GetValue() const/g' "$$ALT_SIGN_INTEGER_CPP"; \
		fi; \
		ALT_SIGN_DATE_CPP="$$ALT_SIGN_LIBPLIST_SRC_DIR/Date.cpp"; \
		if [ -f "$$ALT_SIGN_DATE_CPP" ]; then \
			perl -0pi -e 's/\btimeval\s+t\s*=\s*d\.GetValue\(\);/int64_t t = d.GetValue();/g; s/\bDate::Date\(timeval\s+([A-Za-z_][A-Za-z0-9_]*)\)\b/Date::Date(int64_t $$1)/g; s/\bvoid\s+Date::SetValue\(timeval\s+([A-Za-z_][A-Za-z0-9_]*)\)\b/void Date::SetValue(int64_t $$1)/g; s/\btimeval\s+Date::GetValue\(\)\s+const\b/int64_t Date::GetValue() const/g' "$$ALT_SIGN_DATE_CPP"; \
		fi; \
	else \
		echo "Expected AltSign libplist sources after submodule initialization." >&2; \
		exit 1; \
	fi

$(SCHEMES): prepare_packages
	# Zsign expects <openssl/...> headers; reuse AltSign's vendored XCFramework to avoid a second OpenSSL copy.
	set -e; \
	ALT_SIGN_OPENSSL_XCFRAMEWORK="$$(find "$(ALT_SIGN_PATH)" "$(SOURCE_PACKAGES)" \( -path "*/Dependencies/OpenSSL.xcframework" -o -path "*/OpenSSL.xcframework" \) -type d 2>/dev/null | head -n 1)"; \
	if [ -z "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" ]; then \
		echo "Expected AltSign OpenSSL.xcframework after package resolution." >&2; \
		exit 1; \
	fi; \
	case "$(PLATFORM)" in \
		iphonesimulator) \
			OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/OpenSSL.framework" -type d | grep -i simulator | head -n 1 || true)" ;; \
		*) \
			OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/ios-*/OpenSSL.framework" -type d | grep -vi simulator | grep -vi maccatalyst | head -n 1 || true)"; \
			if [ -z "$$OPENSSL_FRAMEWORK" ]; then \
				OPENSSL_FRAMEWORK="$$(find "$$ALT_SIGN_OPENSSL_XCFRAMEWORK" -path "*/OpenSSL.framework" -type d | grep -vi maccatalyst | head -n 1 || true)"; \
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
