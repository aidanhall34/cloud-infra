# Makefile conventions

- All recipes will have a comment next to the title describing there function.
- After a change to the makefile, the README.md file should be updated by running `make readme`.

# Scripts conventions

- Scripts should be built into a container with the tag -t "aidanhall34/homelab:latest".

# Docs conventions

- All references to module or function names in documentation should contain a link to starting line in the file of the codes declaration.

# Service conventions

- All services should be deploy with JSON logging enabled.
- Services should log to the ./dev/logs directory

# Command execution conventions

- Commands should be run with JSON output
- Commands should log to the ./dev/logs directory

# Python conventions

- Python dependencies should managed in venvs, and installed with the UV package manager.
- Python3.13 is the default version of python to use for applications.
- Python should be typed, and checked with mypy on every change.
- Python tests and type checking can be run by running `make build`
- Python code is linted with `ruff`, and it must be installed in every env as a dependency

# Ansible conventions

- Ansible roles are tested with molecule, tests are executed with `make ansible-molecule`
- Ansible roles linted with `make ansible-lint`
- `molecule` tests should use the `docker` executor. They must be run in `systemd compatible containers`
- Ansible code should be formatted with ansible-list
- Ansible roles and playbooks should always use modules, where a module does not exist online, one should be written.
- Ansible modules should be tested with `ansible-test` and unit tests for modules should be manged with `pytest`.
    To run the module tests, run `make ansible-test` and make `ansible-pytest`
- Ansible and its dependencies should be managed with `uv` and a venv in the ./ansible directory.
- Docs must be generate with `make ansible-doc`

# Packer conventions

- Packer should be validated with `make packer-validate` when changed
- Packer should be formatted with `make packer-fmt`

# Container conventions

- Containers should log to the ./dev/logs directory
