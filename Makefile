SHELL := /bin/sh

SWIFT_REPO := $(CURDIR)
ED_REPO ?= $(abspath ../onde-ed)
MANIFEST := $(ED_REPO)/crates/ed-agent-ffi/Cargo.toml
BINDGEN_MANIFEST := $(ED_REPO)/uniffi-bindgen/Cargo.toml
BINDGEN := $(ED_REPO)/target/release/uniffi-bindgen
APPLE_TARGET_DIR := $(ED_REPO)/target/apple

IOS_DEPLOYMENT_TARGET ?= 16.0
MACOS_DEPLOYMENT_TARGET ?= 14.0
TVOS_DEPLOYMENT_TARGET ?= 16.0
VISIONOS_DEPLOYMENT_TARGET ?= 1.0
WATCHOS_DEPLOYMENT_TARGET ?= 9.0

LOCAL_DIR := $(SWIFT_REPO)/.local
GENERATED_DIR := $(LOCAL_DIR)/generated/Ed
HEADERS_DIR := $(LOCAL_DIR)/Headers
FRAMEWORK_DIR := $(SWIFT_REPO)/EdFramework.xcframework
SWIFT_GLUE := $(SWIFT_REPO)/Sources/Ed/ed_agent_ffi.swift

.PHONY: help ios macos tvos visionos watchos build-bindgen prepare generate-swift clean

help:
	@printf '%s\n' \
	  'Ed Swift local builds' \
	  '' \
	  'make ios | macos | tvos | visionos | watchos' \
	  'Set ED_REPO=/path/to/onde-ed when the repositories are not siblings.'

validate:
	@test -f "$(MANIFEST)" || { echo "Could not find onde-ed at $(ED_REPO)"; exit 1; }

build-bindgen: validate
	cargo build --manifest-path "$(BINDGEN_MANIFEST)" --release

prepare:
	@rm -rf "$(FRAMEWORK_DIR)" "$(GENERATED_DIR)" "$(HEADERS_DIR)"
	@mkdir -p "$(GENERATED_DIR)" "$(HEADERS_DIR)"

generate-swift:
	@test -n "$(BINDGEN_INPUT)" || { echo "BINDGEN_INPUT is required"; exit 1; }
	cd "$(ED_REPO)" && "$(BINDGEN)" generate "$(BINDGEN_INPUT)" --crate ed_agent_ffi --language swift --out-dir "$(GENERATED_DIR)"
	cp "$(GENERATED_DIR)/ed_agent_ffi.swift" "$(SWIFT_GLUE)"
	cp "$(GENERATED_DIR)/ed_agent_ffiFFI.h" "$(HEADERS_DIR)/ed_agent_ffiFFI.h"
	cp "$(GENERATED_DIR)/ed_agent_ffiFFI.modulemap" "$(HEADERS_DIR)/module.modulemap"

ios: build-bindgen prepare
	IPHONEOS_DEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET) cargo rustc --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target aarch64-apple-ios --release --lib --crate-type staticlib
	IPHONEOS_DEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET) cargo rustc --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target aarch64-apple-ios-sim --release --lib --crate-type staticlib
	$(MAKE) generate-swift BINDGEN_INPUT="$(APPLE_TARGET_DIR)/aarch64-apple-ios/release/libed_agent_ffi.a"
	xcodebuild -create-xcframework \
	  -library "$(APPLE_TARGET_DIR)/aarch64-apple-ios/release/libed_agent_ffi.a" -headers "$(HEADERS_DIR)" \
	  -library "$(APPLE_TARGET_DIR)/aarch64-apple-ios-sim/release/libed_agent_ffi.a" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

macos: build-bindgen prepare
	MACOSX_DEPLOYMENT_TARGET=$(MACOS_DEPLOYMENT_TARGET) cargo rustc --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target aarch64-apple-darwin --release --lib --crate-type staticlib
	$(MAKE) generate-swift BINDGEN_INPUT="$(APPLE_TARGET_DIR)/aarch64-apple-darwin/release/libed_agent_ffi.a"
	xcodebuild -create-xcframework \
	  -library "$(APPLE_TARGET_DIR)/aarch64-apple-darwin/release/libed_agent_ffi.a" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

tvos: build-bindgen prepare
	TVOS_DEPLOYMENT_TARGET=$(TVOS_DEPLOYMENT_TARGET) cargo +nightly rustc -Z build-std --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target aarch64-apple-tvos --release --lib --crate-type staticlib
	TVOS_DEPLOYMENT_TARGET=$(TVOS_DEPLOYMENT_TARGET) cargo +nightly rustc -Z build-std --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target aarch64-apple-tvos-sim --release --lib --crate-type staticlib
	$(MAKE) generate-swift BINDGEN_INPUT="$(APPLE_TARGET_DIR)/aarch64-apple-tvos/release/libed_agent_ffi.a"
	xcodebuild -create-xcframework \
	  -library "$(APPLE_TARGET_DIR)/aarch64-apple-tvos/release/libed_agent_ffi.a" -headers "$(HEADERS_DIR)" \
	  -library "$(APPLE_TARGET_DIR)/aarch64-apple-tvos-sim/release/libed_agent_ffi.a" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

visionos: build-bindgen prepare
	XROS_DEPLOYMENT_TARGET=$(VISIONOS_DEPLOYMENT_TARGET) cargo +nightly rustc -Z build-std --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target aarch64-apple-visionos --release --lib --crate-type staticlib
	XROS_DEPLOYMENT_TARGET=$(VISIONOS_DEPLOYMENT_TARGET) cargo +nightly rustc -Z build-std --target-dir "$(APPLE_TARGET_DIR)" --manifest-path "$(MANIFEST)" --target aarch64-apple-visionos-sim --release --lib --crate-type staticlib
	$(MAKE) generate-swift BINDGEN_INPUT="$(APPLE_TARGET_DIR)/aarch64-apple-visionos/release/libed_agent_ffi.a"
	xcodebuild -create-xcframework \
	  -library "$(APPLE_TARGET_DIR)/aarch64-apple-visionos/release/libed_agent_ffi.a" -headers "$(HEADERS_DIR)" \
	  -library "$(APPLE_TARGET_DIR)/aarch64-apple-visionos-sim/release/libed_agent_ffi.a" -headers "$(HEADERS_DIR)" \
	  -output "$(FRAMEWORK_DIR)"

clean:
	rm -rf "$(FRAMEWORK_DIR)" "$(LOCAL_DIR)"
