#!/usr/bin/env python3
"""Static guard for FIXED105 request batching; run with python3 Tests/verify_fixed105.py."""
from pathlib import Path
source = (Path(__file__).resolve().parents[1] / "HOTEL_SHIFT/Services/ShiftStore.swift").read_text()
start = source.index("    func addRequests(staffID:")
end = source.index("    func setRequestStatus(", start)
body = source[start:end]
assert "existingKeys.insert(key).inserted" in body
assert "if changed { data.requests = requests }" in body
assert "requests.contains(where:" not in body
print("FIXED105 request batching regression checks passed")
