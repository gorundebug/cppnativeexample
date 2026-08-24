.PHONY: docker-build docker-up docker-down conan-lock clean

docker-build:
	@./scripts/docker-build-target.sh inventoryservice cppnativeexample-inventoryservice:latest
	@./scripts/docker-build-target.sh orderservice cppnativeexample-orderservice:latest

docker-up: docker-build
	@bash -c 'source scripts/dependency-proxy-env.sh && docker compose up -d --no-build'

docker-down:
	@docker compose down --volumes --remove-orphans

conan-lock:
	@./scripts/conan-lock.sh

clean:
	@docker compose down --volumes --remove-orphans
