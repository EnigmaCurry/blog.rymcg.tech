.PHONY: build
build: setup
	hugo
	@echo "Site built in ./public"

.PHONY: clean
clean:
	rm -rf ./public

.PHONY: setup
setup:
	git submodule update --init --recursive

.PHONY: serve
serve:
	hugo serve

