.PHONY: download build verify shellcheck

download:
	./download-base-image.sh

build:
	@if [ "$$(uname -s)" = Darwin ]; then ./build-on-macos.sh; else sudo -E ./build-linux.sh; fi

verify:
	@if [ "$$(uname -s)" = Darwin ]; then \
	  . ./image.conf; \
	  container run --rm --cpus 4 --memory 4G \
	    --mount "type=bind,source=$$PWD,target=/work" \
	    docker.io/library/debian:trixie-slim bash -lc \
	    "apt-get update >/dev/null && apt-get install -y --no-install-recommends e2fsprogs util-linux openssh-client >/dev/null && PACKAGES_FILE=/work/packages.txt /work/verify-image.sh /work/output/$$BASE_NAME-usb-debug.img /work/output/authorized_key.pub"; \
	else \
	  . ./image.conf; \
	  sudo PACKAGES_FILE="$$PWD/packages.txt" ./verify-image.sh \
	    "$${OUTPUT_DIR:-$$PWD/output}/$$BASE_NAME-usb-debug.img" "$${SSH_PUBLIC_KEY_FILE:?set SSH_PUBLIC_KEY_FILE}"; \
	fi

shellcheck:
		bash -n build-on-macos.sh build-linux.sh customize-image.sh \
		  verify-image.sh download-base-image.sh compress-image.sh
		dash -n pi-help
	@if command -v shellcheck >/dev/null; then shellcheck ./*.sh pi-help; fi
