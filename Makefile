.PHONY: update update-theme dev build

update:
	CGO_ENABLED=1 go install -tags extended,withdeploy github.com/gohugoio/hugo@latest
	$(MAKE) update-theme

update-theme:
	git submodule update --init --recursive
	git submodule update --remote --merge

# 本地预览
dev:
	hugo server -D --disableFastRender

# 正式构建
build:
	hugo --gc --minify
