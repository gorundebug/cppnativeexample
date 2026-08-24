.PHONY: docker-build docker-up docker-down conan-lock clean

docker-build:
	@bash -c 'source scripts/dependency-proxy-env.sh && docker compose build'

docker-up:
	@bash -c 'source scripts/dependency-proxy-env.sh && docker compose up -d --build'

docker-down:
	@docker compose down --volumes --remove-orphans

conan-lock:
	@./scripts/conan-lock.sh

clean:
	@docker compose down --volumes --remove-orphans
