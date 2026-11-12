# Load .env into every recipe
ifneq (,$(wildcard .env))
include .env
export
endif

DBT = cd dbt && dbt
DBT_FLAGS = --profiles-dir .

.PHONY: install test lint seed simulate dbt-deps dbt-build freshness docs

install:            ## Install Python and dbt dependencies
	pip install -r requirements-dev.txt
	$(DBT) deps $(DBT_FLAGS)

test:               ## Unit tests for the simulator
	pytest -q

lint:
	ruff check .

seed:               ## Load the public dataset and issue the first 50k policies
	python -m simulator.seed --initial-policies 50000

simulate:           ## 20 batches of 500 events, every 30 s (~1.4M events/day rate)
	python -m simulator.legacy_simulator --events-per-batch 500 --batches 20 --interval-seconds 30

dbt-build:          ## Run and test every model
	$(DBT) build $(DBT_FLAGS)

freshness:          ## Is the CDC change log up to date?
	$(DBT) source freshness $(DBT_FLAGS)

docs:
	$(DBT) docs generate $(DBT_FLAGS) && $(DBT) docs serve $(DBT_FLAGS)
