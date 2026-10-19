PY := .venv/bin/python
PIP := .venv/bin/pip

.PHONY: install dev test test-live models reembed docker

install:
	python3 -m venv .venv
	$(PIP) install -q --upgrade pip
	$(PIP) install -q -e ".[dev]"

dev:
	$(PY) -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

test:
	$(PY) -m pytest -q

test-live:
	$(PY) -m pytest -q -m live tests/test_router_golden.py

models:
	$(PY) -m scripts.list_models

reembed:
	$(PY) -m scripts.reembed

docker:
	docker build -t spaces-backend .
