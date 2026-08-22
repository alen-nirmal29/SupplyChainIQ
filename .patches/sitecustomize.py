import hashlib as _hashlib

_orig_md5 = _hashlib.md5


def _patched_md5(*args, **kwargs):
    kwargs.setdefault("usedforsecurity", False)
    return _orig_md5(*args, **kwargs)


_hashlib.md5 = _patched_md5
