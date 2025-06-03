install:
	./scripts/iac/install.sh

apply:
	@for file in ./rules/*.yaml; do \
		l9iac -mf $$file -c ./config.json apply; \
	done

plan:
	@for file in ./rules/*.yaml; do \
		l9iac -mf $$file -c ./config.json plan; \
	done

