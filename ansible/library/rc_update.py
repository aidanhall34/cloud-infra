# -*- coding: utf-8 -*-
"""Ansible module to manage OpenRC service runlevel assignments via rc-update."""

from __future__ import annotations

import os
from typing import Any

from ansible.module_utils.basic import AnsibleModule

DOCUMENTATION = r"""
---
module: rc_update
short_description: Manage OpenRC service runlevel assignments
description:
  - Add or remove an OpenRC service from a runlevel using C(rc-update).
  - Idempotent — checks C(/etc/runlevels/<runlevel>/<name>) before acting.
options:
  name:
    description: Name of the OpenRC service to manage.
    required: true
    type: str
  runlevel:
    description: Runlevel to add or remove the service from.
    required: false
    default: default
    type: str
  state:
    description:
      - C(present) ensures the service is in the runlevel.
      - C(absent) ensures the service is not in the runlevel.
    required: false
    default: present
    choices: [present, absent]
    type: str
requirements:
  - rc-update (part of OpenRC)
"""

EXAMPLES = r"""
- name: Enable sshd at default runlevel
  rc_update:
    name: sshd
    runlevel: default
    state: present

- name: Remove ntpd from default runlevel
  rc_update:
    name: ntpd
    state: absent
"""

RETURN = r"""
name:
  description: Service name acted upon.
  returned: always
  type: str
  sample: sshd
runlevel:
  description: Runlevel acted upon.
  returned: always
  type: str
  sample: default
state:
  description: Desired state.
  returned: always
  type: str
  sample: present
"""


def is_enabled(name: str, runlevel: str) -> bool:
    """Return True if the service symlink already exists in the runlevel."""
    return os.path.exists(f"/etc/runlevels/{runlevel}/{name}")


def main() -> None:
    module: AnsibleModule = AnsibleModule(
        argument_spec=dict(
            name=dict(type="str", required=True),
            runlevel=dict(type="str", default="default"),
            state=dict(type="str", default="present", choices=["present", "absent"]),
        ),
        supports_check_mode=True,
    )

    name: str = module.params["name"]
    runlevel: str = module.params["runlevel"]
    state: str = module.params["state"]

    currently_enabled: bool = is_enabled(name, runlevel)
    want_enabled: bool = state == "present"

    result: dict[str, Any] = dict(name=name, runlevel=runlevel, state=state)

    if currently_enabled == want_enabled:
        module.exit_json(changed=False, **result)
        return

    if module.check_mode:
        module.exit_json(changed=True, **result)
        return

    action = "add" if want_enabled else "del"
    rc, _stdout, stderr = module.run_command(["rc-update", action, name, runlevel])

    if rc != 0:
        module.fail_json(
            msg=f"rc-update {action} {name} {runlevel} failed: {stderr.strip()}",
            rc=rc,
            **result,
        )

    module.exit_json(changed=True, **result)


if __name__ == "__main__":
    main()
