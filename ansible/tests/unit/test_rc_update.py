"""Unit tests for the rc_update Ansible module."""

from __future__ import annotations

import sys
import os
from typing import Any
from unittest.mock import MagicMock, patch

# Add the library directory to sys.path so the module can be imported
# without a full Ansible installation providing the package structure.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "library"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_module(
    name: str = "sshd",
    runlevel: str = "default",
    state: str = "present",
    check_mode: bool = False,
) -> MagicMock:
    """Return a mock AnsibleModule pre-configured with the given params."""
    module = MagicMock()
    module.params = {"name": name, "runlevel": runlevel, "state": state}
    module.check_mode = check_mode
    module.run_command.return_value = (0, "", "")
    return module


# ---------------------------------------------------------------------------
# is_enabled
# ---------------------------------------------------------------------------

class TestIsEnabled:
    def test_returns_true_when_symlink_exists(self) -> None:
        from rc_update import is_enabled

        with patch("os.path.exists", return_value=True) as mock_exists:
            assert is_enabled("sshd", "default") is True
            mock_exists.assert_called_once_with("/etc/runlevels/default/sshd")

    def test_returns_false_when_symlink_missing(self) -> None:
        from rc_update import is_enabled

        with patch("os.path.exists", return_value=False):
            assert is_enabled("ntpd", "sysinit") is False

    def test_builds_correct_path(self) -> None:
        from rc_update import is_enabled

        with patch("os.path.exists", return_value=True) as mock_exists:
            is_enabled("chronyd", "boot")
            mock_exists.assert_called_once_with("/etc/runlevels/boot/chronyd")


# ---------------------------------------------------------------------------
# main — no-op cases (already in desired state)
# ---------------------------------------------------------------------------

class TestMainNoChange:
    def test_present_and_already_enabled_exits_not_changed(self) -> None:
        from rc_update import main

        module = make_module(state="present")
        with (
            patch("rc_update.AnsibleModule", return_value=module),
            patch("rc_update.is_enabled", return_value=True),
        ):
            main()

        module.exit_json.assert_called_once_with(
            changed=False, name="sshd", runlevel="default", state="present"
        )
        module.run_command.assert_not_called()

    def test_absent_and_already_disabled_exits_not_changed(self) -> None:
        from rc_update import main

        module = make_module(state="absent")
        with (
            patch("rc_update.AnsibleModule", return_value=module),
            patch("rc_update.is_enabled", return_value=False),
        ):
            main()

        module.exit_json.assert_called_once_with(
            changed=False, name="sshd", runlevel="default", state="absent"
        )
        module.run_command.assert_not_called()


# ---------------------------------------------------------------------------
# main — check mode (state change would happen but is suppressed)
# ---------------------------------------------------------------------------

class TestMainCheckMode:
    def test_check_mode_exits_changed_without_running_command(self) -> None:
        from rc_update import main

        module = make_module(state="present", check_mode=True)
        with (
            patch("rc_update.AnsibleModule", return_value=module),
            patch("rc_update.is_enabled", return_value=False),
        ):
            main()

        module.exit_json.assert_called_once_with(
            changed=True, name="sshd", runlevel="default", state="present"
        )
        module.run_command.assert_not_called()


# ---------------------------------------------------------------------------
# main — state changes (rc-update called)
# ---------------------------------------------------------------------------

class TestMainStateChange:
    def test_adds_service_when_not_present(self) -> None:
        from rc_update import main

        module = make_module(state="present")
        with (
            patch("rc_update.AnsibleModule", return_value=module),
            patch("rc_update.is_enabled", return_value=False),
        ):
            main()

        module.run_command.assert_called_once_with(
            ["rc-update", "add", "sshd", "default"]
        )
        module.exit_json.assert_called_once_with(
            changed=True, name="sshd", runlevel="default", state="present"
        )

    def test_removes_service_when_present(self) -> None:
        from rc_update import main

        module = make_module(state="absent")
        with (
            patch("rc_update.AnsibleModule", return_value=module),
            patch("rc_update.is_enabled", return_value=True),
        ):
            main()

        module.run_command.assert_called_once_with(
            ["rc-update", "del", "sshd", "default"]
        )
        module.exit_json.assert_called_once_with(
            changed=True, name="sshd", runlevel="default", state="absent"
        )

    def test_uses_custom_runlevel(self) -> None:
        from rc_update import main

        module = make_module(name="chronyd", runlevel="boot", state="present")
        with (
            patch("rc_update.AnsibleModule", return_value=module),
            patch("rc_update.is_enabled", return_value=False),
        ):
            main()

        module.run_command.assert_called_once_with(
            ["rc-update", "add", "chronyd", "boot"]
        )


# ---------------------------------------------------------------------------
# main — rc-update command failure
# ---------------------------------------------------------------------------

class TestMainCommandFailure:
    def test_fails_when_rc_update_returns_nonzero(self) -> None:
        from rc_update import main

        module = make_module(state="present")
        module.run_command.return_value = (1, "", "service not found")
        with (
            patch("rc_update.AnsibleModule", return_value=module),
            patch("rc_update.is_enabled", return_value=False),
        ):
            main()

        module.fail_json.assert_called_once()
        call_kwargs: dict[str, Any] = module.fail_json.call_args.kwargs
        assert "service not found" in call_kwargs["msg"]
        assert call_kwargs["rc"] == 1
