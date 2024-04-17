build_and_push:
	git tag -a "$(version)" -f -m "$(version)"
	docker build . -t dawarich:$(version) --platform=linux/amd64
	docker tag dawarich:$(version) registry.chibi.rodeo/dawarich:$(version)
	docker tag registry.chibi.rodeo/dawarich:$(version) registry.chibi.rodeo/dawarich:latest
	docker push registry.chibi.rodeo/dawarich:$(version)
