.PHONY: update install-hugo update-hugo update-theme dev build

HUGO_MODULE := github.com/gohugoio/hugo
HUGO_VERSION_FILE := .hugo-version
HUGO_VERSION := $(shell sed -n '1{s/^v//;p;}' $(HUGO_VERSION_FILE) 2>/dev/null)

install-hugo:
	@test -n "$(HUGO_VERSION)" || (echo "$(HUGO_VERSION_FILE) is missing or empty" >&2; exit 1)
	CGO_ENABLED=1 go install -tags extended,withdeploy $(HUGO_MODULE)@v$(HUGO_VERSION)

update-hugo:
	@version=$$(go list -m -f '{{ .Version }}' $(HUGO_MODULE)@latest | sed 's/^v//'); \
	printf '%s\n' "$$version" > $(HUGO_VERSION_FILE); \
	CGO_ENABLED=1 go install -tags extended,withdeploy $(HUGO_MODULE)@v$$version

update-theme:
	git submodule update --init --recursive
	git submodule update --remote --merge

# 更新hugo和主题
update: update-hugo update-theme

# 本地预览
dev:
	hugo server -D --disableFastRender

# 正式构建
build:
	hugo --gc --minify
