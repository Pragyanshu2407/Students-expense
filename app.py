# This file is superseded by run.py + the tracker/ package (Phase 1 refactor).
# It is kept only so that existing import references don't cause hard errors.
# Entry point is now:  python run.py

from tracker import create_app  # noqa: F401

app = create_app()
