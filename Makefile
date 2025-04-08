# Makefile

SHELL := /bin/bash

.PHONY: lint
lint:
	shellcheck *.sh *.conf